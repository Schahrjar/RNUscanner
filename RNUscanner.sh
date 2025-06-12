#!/bin/bash

set -euo pipefail

# Shahryar Alavi
# UCL Institute of Neurology, London, UK
# 2025-06-11

# Initialize variables
BED_FILE=""
BAM_LIST=""
REFERENCE_FASTA=""
VARIANT_ANNOTATION_VCF=""
OUTPUT_DIR="RNUscanner_out"
SAMTOOLS_PATH="samtools"
BCFTOOLS_PATH="bcftools"
LOG_FILE="" # For logging output

# Parse named arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --gene-list)
            BED_FILE="$2"
            shift 2
            ;;
        --bam-list)
            BAM_LIST="$2"
            shift 2
            ;;
        --reference)
            REFERENCE_FASTA="$2"
            shift 2
            ;;
        --variant-annotation)
            VARIANT_ANNOTATION_VCF="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --samtools-path)
            SAMTOOLS_PATH="$2"
            shift 2
            ;;
        --bcftools-path)
            BCFTOOLS_PATH="$2"
            shift 2
            ;;
        --help)
            echo ""
            echo "Usage: $0 --gene-list <BED_FILE> --bam-list <BAM_LIST> --reference <REFERENCE_FASTA> [--variant-annotation <VARIANT_VCF>] [--output-dir <OUTPUT_DIR>] [--samtools-path <SAMTOOLS>] [--bcftools-path <BCFTOOLS>]"
            echo -e "\nRNUscanner\tversion 1.00\t2025-06-11"
            echo ""
            echo "Arguments:"
            echo "  --gene-list          BED file with regions of interest (e.g., RNU-loci.bed)"
            echo "                       (Format: chromosome, start, end, gene/locus name; no header)"
            echo ""
            echo "  --bam-list           Text file listing paths to BAM files, one per line."
            echo ""
            echo "  --reference          FASTA file of the reference genome, used for BAM files, and must be indexed (.fai required)."
            echo ""
            echo "  --variant-annotation (ptional) VCF file containing known variants for annotation. (default: VCF is not provided and annotation is disabled)"
            echo "                       (Example: VCF with INFO fields for GENE and SIGNIFICANCE, and populated ID field)"
            echo "                       If provided, RNUscanner will automatically bgzip-compress and tabix-index this file if needed."
            echo ""
            echo "  --output-dir         (optional) Directory to store output VCFs and logs (default: RNUscanner_out). Will be created if it doesn't exist."
            echo ""
            echo "  --samtools-path      (optional) Path to samtools executable (default: samtools)."
            echo ""
            echo "  --bcftools-path      (optional) Path to bcftools executable (default: bcftools)."
            echo ""
            echo "Notes:"
            echo "  - Calls variants using bcftools."
            echo "  - Optionally annotates variants if an input VCF is provided."
            echo "  - Creates per-sample VCF files if variants are found in the target regions."
            echo "  - This script is suitable for variant screening in low-depth or segmental duplication regions, which their variants are missed by usual variant callings."
            echo ""
            echo "  MIT License | Copyright (c) 2025 Shahryar Alavi"
            echo ""
            echo "  Repository: https://github.com/Schahrjar/RNUscanner"
            echo ""
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            exit 1
            ;;
    esac
done

# --- Argument Validation ---
# Check for required core arguments
if [[ -z "$BED_FILE" || -z "$BAM_LIST" || -z "$REFERENCE_FASTA" ]]; then
    echo "❌ Missing required argument(s): --gene-list, --bam-list, and --reference are mandatory. Use --help for usage."
    exit 1
fi

# Validate files
[[ ! -f "$BED_FILE" ]] && { echo "❌ BED file not found: $BED_FILE"; exit 1; }
[[ ! -f "$BAM_LIST" ]] && { echo "❌ BAM list not found: $BAM_LIST"; exit 1; }
[[ ! -f "$REFERENCE_FASTA" ]] && { echo "❌ Reference FASTA not found: $REFERENCE_FASTA"; exit 1; }
[[ ! -f "${REFERENCE_FASTA}.fai" ]] && { echo "❌ Reference FASTA index (${REFERENCE_FASTA}.fai) not found. Please index your reference FASTA with '$SAMTOOLS_PATH faidx ${REFERENCE_FASTA}' or '$BCFTOOLS_PATH faidx ${REFERENCE_FASTA}'."; exit 1; }

# --- Tool Validation ---
command -v "$SAMTOOLS_PATH" >/dev/null 2>&1 || { echo "❌ samtools not found or not executable at: $SAMTOOLS_PATH"; exit 1; }
command -v "$BCFTOOLS_PATH" >/dev/null 2>&1 || { echo "❌ bcftools not found or not executable at: $BCFTOOLS_PATH"; exit 1; }

# Robust bcftools version check
# Extract major and minor version numbers
read -r BCFTOOLS_MAJOR_VER BCFTOOLS_MINOR_VER < <("$BCFTOOLS_PATH" --version | head -n1 | awk '{split($2, v, "."); print v[1], v[2]}')

if (( BCFTOOLS_MAJOR_VER < 1 )) || \
   (( BCFTOOLS_MAJOR_VER == 1 && BCFTOOLS_MINOR_VER < 19 )); then
    echo "❌ Your bcftools version ($BCFTOOLS_MAJOR_VER.$BCFTOOLS_MINOR_VER) is too old. Please update to 1.19 or higher for --trim-unseen-allele and other features."
    exit 1
fi


# --- Setup Output and Logging ---
mkdir -p "$OUTPUT_DIR"
LOG_FILE="${OUTPUT_DIR}/RNUscanner.log"
exec > >(tee -a "$LOG_FILE") 2>&1 # Redirect all stdout and stderr to log file and console
echo "--- RNUscanner Log - $(date) ---"
echo "Output directory: $OUTPUT_DIR"
echo "Reference FASTA: $REFERENCE_FASTA"

# --- Prepare Temporary Directory ---
TEMP_DIR=$(mktemp -d "${OUTPUT_DIR}/temp.XXXXXXXXXX") # Create temp dir inside output dir
trap 'rm -rf "$TEMP_DIR"' EXIT # Clean up temp dir on exit

# --- Process Optional Annotation VCF ---
ANNOTATION_ENABLED="false"
if [[ -n "$VARIANT_ANNOTATION_VCF" ]]; then # Check if the variable is non-empty
    ANNOTATION_ENABLED="true"
    original_annot_vcf_path="$VARIANT_ANNOTATION_VCF" # Store original path for reference

    # Check if already bgzipped (ends with .vcf.gz)
    if [[ "$original_annot_vcf_path" == *.vcf.gz ]]; then
        echo "Info: Annotation VCF is already bgzip-compressed: $original_annot_vcf_path"
        
        # Check for index: prioritize .tbi, then .csi
        if [[ -f "${original_annot_vcf_path}.tbi" ]]; then
            echo "Info: Tabix index (${original_annot_vcf_path}.tbi) found."
        elif [[ -f "${original_annot_vcf_path}.csi" ]]; then
            echo "Info: CSI index (${original_annot_vcf_path}.csi) found."
        else
            # No index found, create one (bcftools index defaults to .tbi for VCFs)
            echo "Info: No index found for "$original_annot_vcf_path". Creating index..."
            "$BCFTOOLS_PATH" index -f "$original_annot_vcf_path" || { echo "❌ Failed to index "$original_annot_vcf_path". Exiting."; exit 1; }
        fi
        # If already .vcf.gz and indexed, VARIANT_ANNOTATION_VCF remains as is.
    elif [[ "$original_annot_vcf_path" == *.vcf ]]; then
        # Plain VCF, needs compression and indexing
        new_annot_vcf_gz="${original_annot_vcf_path}.gz"
        echo "Info: Annotation VCF is not bgzip-compressed. Compressing to "$new_annot_vcf_gz"..."
        # Use bcftools view -Oz for compression
        "$BCFTOOLS_PATH" view "$original_annot_vcf_path" -Oz -o "$new_annot_vcf_gz" || { echo "❌ Failed to compress "$original_annot_vcf_path" with bcftools view -Oz. Exiting."; exit 1; }
        
        VARIANT_ANNOTATION_VCF="$new_annot_vcf_gz" # Update the variable for subsequent use in the pipeline

        echo "Info: Creating index for "$VARIANT_ANNOTATION_VCF"..."
        "$BCFTOOLS_PATH" index -f "$VARIANT_ANNOTATION_VCF" || { echo "❌ Failed to index "$VARIANT_ANNOTATION_VCF". Exiting."; exit 1; }
    else
        # Not .vcf or .vcf.gz, warn and disable annotation
        echo "⚠️ Warning: Invalid format for --variant-annotation ("$original_annot_vcf_path"). Expected .vcf or .vcf.gz. Annotation disabled for this run."
        ANNOTATION_ENABLED="false"
    fi
fi

if [[ "$ANNOTATION_ENABLED" == "true" ]]; then
    echo "Variant Annotation VCF: "$VARIANT_ANNOTATION_VCF" (Optional annotation enabled)"
else
    echo "No Variant Annotation VCF provided, or it was in an unsupported format. Output VCFs will not be annotated with custom INFO/ID fields."
fi

# --- Main Processing Loop ---
while read -r BAM_PATH; do
    # Skip empty lines in BAM list
    [[ -z "$BAM_PATH" ]] && continue

    # Validate BAM file existence
    [[ ! -f "$BAM_PATH" ]] && { echo "⚠️ BAM file not found: "$BAM_PATH" — skipping."; continue; }

    # Get sample name from BAM header (more robust than basename)
    if "$SAMTOOLS_PATH" --version | head -n 1 | grep -q "1\.[1-9][0-9]*\|[2-9]\."; then # samtools >= 1.10
        SAMPLE=$("$SAMTOOLS_PATH" samples "$BAM_PATH" | cut -f1)
    else # Fallback for older samtools or if 'samples' command isn't present
        SAMPLE=$(basename "$BAM_PATH" .bam)
        echo "Using basename to infer sample name for "$BAM_PATH". Consider updating samtools (v1.14+ recommended for 'samples' command)."
    fi

    echo "--- Processing sample: "$SAMPLE" ---"

    TEMP_MPILEUP_VCF="${TEMP_DIR}/${SAMPLE}.mpileup.vcf"
    TEMP_NORM_VCF="${TEMP_DIR}/${SAMPLE}.norm.vcf"
    TEMP_VIEW_VCF="${TEMP_DIR}/${SAMPLE}.view.vcf"
    TEMP_GENE_ANNOTATED_VCF="${TEMP_DIR}/${SAMPLE}.gene_annotated.vcf"
    TEMP_GENE_ANNOTATED_VCF_GZ="${TEMP_DIR}/${SAMPLE}.gene_annotated.vcf.gz" 
    TEMP_ANNOTATE_VCF="${TEMP_DIR}/${SAMPLE}.annotate.vcf" 
    FINAL_VCF="${OUTPUT_DIR}/${SAMPLE}.vcf"

    # Step 1: bcftools mpileup (outputs plain VCF)
    echo "Running bcftools mpileup..."
    if ! "$BCFTOOLS_PATH" mpileup \
        --fasta-ref "$REFERENCE_FASTA" \
        --regions-file "$BED_FILE" \
        --count-orphans \
        --min-BQ 0 \
        -a AD,DP \
        --threads 4 \
        "$BAM_PATH" \
    > "$TEMP_MPILEUP_VCF"; then
        echo "❌ bcftools mpileup failed for sample "$SAMPLE" (BAM: "$BAM_PATH"). This often indicates an issue with the BAM file itself (e.g., corruption, bad permissions, incomplete transfer) or the file system. Skipping this sample."
        continue # Skip to the next BAM in the list
    fi

    # Check if mpileup produced output, otherwise remaining steps will fail
    if [[ ! -s "$TEMP_MPILEUP_VCF" ]]; then
        echo "⚠️ bcftools mpileup produced no output for "$SAMPLE". This might indicate no variants in regions or a minor issue. Skipping subsequent VCF processing for this sample."
        rm -f "$TEMP_MPILEUP_VCF" # Clean up the potentially empty/malformed file
        continue
    fi

    # Step 2: bcftools norm (outputs plain VCF)
    echo "Running bcftools norm..."
    # Add error handling for bcftools norm
    if ! "$BCFTOOLS_PATH" norm -Ov -f "$REFERENCE_FASTA" "$TEMP_MPILEUP_VCF" \
    > "$TEMP_NORM_VCF"; then
        echo "❌ bcftools norm failed for sample "$SAMPLE". Skipping this sample."
        rm -f "$TEMP_MPILEUP_VCF" "$TEMP_NORM_VCF" 2>/dev/null || true # Clean up
        continue
    fi
    
    # Check if norm produced output
    if [[ ! -s "$TEMP_NORM_VCF" ]]; then
        echo "⚠️ bcftools norm produced no output for "$SAMPLE". Skipping subsequent VCF processing for this sample."
        rm -f "$TEMP_MPILEUP_VCF" "$TEMP_NORM_VCF" 2>/dev/null || true # Clean up
        continue
    fi

    # Step 3: bcftools view (outputs plain VCF)
    echo "Running bcftools view..."
    # Add error handling for bcftools view
    if ! "$BCFTOOLS_PATH" view --trim-unseen-allele -Ov "$TEMP_NORM_VCF" \
    > "$TEMP_VIEW_VCF"; then
        echo "❌ bcftools view failed for sample "$SAMPLE". Skipping this sample."
        rm -f "$TEMP_MPILEUP_VCF" "$TEMP_NORM_VCF" "$TEMP_VIEW_VCF" 2>/dev/null || true # Clean up
        continue
    fi

    # Check if view produced output
    if [[ ! -s "$TEMP_VIEW_VCF" ]]; then
        echo "⚠️ bcftools view produced no output for "$SAMPLE". Skipping subsequent VCF processing for this sample."
        rm -f "$TEMP_MPILEUP_VCF" "$TEMP_NORM_VCF" "$TEMP_VIEW_VCF" 2>/dev/null || true # Clean up
        continue
    fi

    # Step 4: Annotate with Gene name from BED file (unconditional for all variants in target regions)
    echo "Annotating variants with Gene names from BED file..."
    if ! "$BCFTOOLS_PATH" annotate \
        -a "$BED_FILE" \
        -c 'CHROM,FROM,TO,INFO/GENE' \
        --header-lines <(echo '##INFO=<ID=GENE,Number=.,Type=String,Description="Gene name from the input BED file.">') \
        -Ov "$TEMP_VIEW_VCF" \
    > "$TEMP_GENE_ANNOTATED_VCF"; then
        echo "❌ bcftools annotate (BED) failed for sample "$SAMPLE". Skipping this sample."
        rm -f "$TEMP_MPILEUP_VCF" "$TEMP_NORM_VCF" "$TEMP_VIEW_VCF" "$TEMP_GENE_ANNOTATED_VCF" 2>/dev/null || true # Clean up
        continue
    fi

    # Step 5: Compress and index the gene-annotated VCF
    echo "Compressing and indexing gene-annotated VCF for further processing..."
    if ! "$BCFTOOLS_PATH" view "$TEMP_GENE_ANNOTATED_VCF" -Oz -o "$TEMP_GENE_ANNOTATED_VCF_GZ"; then
        echo "❌ Compression (bcftools view -Oz) failed for sample "$SAMPLE". Skipping this sample."
        rm -f "$TEMP_MPILEUP_VCF" "$TEMP_NORM_VCF" "$TEMP_VIEW_VCF" "$TEMP_GENE_ANNOTATED_VCF" "$TEMP_GENE_ANNOTATED_VCF_GZ" 2>/dev/null || true # Clean up
        continue
    fi
    if ! "$BCFTOOLS_PATH" index "$TEMP_GENE_ANNOTATED_VCF_GZ"; then
        echo "❌ Indexing (bcftools index) failed for sample "$SAMPLE". Skipping this sample."
        rm -f "$TEMP_MPILEUP_VCF" "$TEMP_NORM_VCF" "$TEMP_VIEW_VCF" "$TEMP_GENE_ANNOTATED_VCF" "$TEMP_GENE_ANNOTATED_VCF_GZ" 2>/dev/null || true # Clean up
        continue
    fi


    # Step 6: Conditional Annotation with VARIANT_VCF (if provided)
    if [[ "$ANNOTATION_ENABLED" == "true" ]]; then
        echo "Running bcftools annotate with known variants VCF..."
        if ! "$BCFTOOLS_PATH" annotate \
            -a "$VARIANT_ANNOTATION_VCF" \
            -c 'ID,INFO/GENE,INFO/SIGNIFICANCE' \
            -Ov "$TEMP_GENE_ANNOTATED_VCF_GZ" \
        > "$TEMP_ANNOTATE_VCF"; then
            echo "❌ bcftools annotate (known variants) failed for sample "$SAMPLE". Skipping this sample."
            rm -f "$TEMP_MPILEUP_VCF" "$TEMP_NORM_VCF" "$TEMP_VIEW_VCF" "$TEMP_GENE_ANNOTATED_VCF" "$TEMP_GENE_ANNOTATED_VCF_GZ" "$TEMP_ANNOTATE_VCF" 2>/dev/null || true # Clean up
            continue
        fi
        INPUT_FOR_FILTER="$TEMP_ANNOTATE_VCF"
    else
        INPUT_FOR_FILTER="$TEMP_GENE_ANNOTATED_VCF_GZ"
    fi

    # Step 7: bcftools filter and final output
    echo "Running bcftools filter and writing final VCF..."
    if ! "$BCFTOOLS_PATH" filter -e 'ALT="<*>"' -Ov "$INPUT_FOR_FILTER" \
    > "$FINAL_VCF"; then
        echo "❌ bcftools filter failed for sample "$SAMPLE". Skipping this sample."
        rm -f "$TEMP_MPILEUP_VCF" "$TEMP_NORM_VCF" "$TEMP_VIEW_VCF" "$TEMP_GENE_ANNOTATED_VCF" "$TEMP_GENE_ANNOTATED_VCF_GZ" "$TEMP_ANNOTATE_VCF" "$FINAL_VCF" 2>/dev/null || true # Clean up
        continue
    fi

    # Clean up intermediate temporary files
    rm -f "$TEMP_MPILEUP_VCF" "$TEMP_NORM_VCF" "$TEMP_VIEW_VCF" \
          "$TEMP_GENE_ANNOTATED_VCF" "$TEMP_GENE_ANNOTATED_VCF_GZ" \
          "$TEMP_ANNOTATE_VCF" 2>/dev/null || true

    # Check if the final VCF actually contains variants
    if [[ -s "$FINAL_VCF" ]] && "$BCFTOOLS_PATH" query -f '%POS\n' "$FINAL_VCF" | grep -q .; then
        echo "✅ Variants detected. Wrote: "$FINAL_VCF""
    else
        echo "ℹ️ No variants detected for "$SAMPLE" in target regions – deleting empty VCF."
        rm -f "$FINAL_VCF"
    fi

done < "$BAM_LIST"

echo "--- All samples processed successfully ---"
echo "Log file: "$LOG_FILE""
