#!/usr/bin/env bash
set -euo pipefail

# By Shahryar Alavi
# UCL Institute of Neurology
# 2025-06-07
# s.alavi@ucl.ac.uk

# This uses samtools to report any mismatches between sequence reads and the reference genome on desired regions.
# Useful for off-target regions of exome data, mainly developed for screening datasets for variants of RNU genes.
# A colourful log file will also be created to make you happy!

# -------------------------------
# Usage Info
# -------------------------------

usage() {
  echo ""
  echo -e "RNUscanner\tversion 1.0\t2025-06-07"
  echo ""
  echo "Usage: $0 \\"
  echo "          --gene-list BED_FILE \\"
  echo "          --bam-list BAM_LIST_FILE \\"
  echo "          --output-dir OUTPUT_DIR \\"
  echo "          --reference REFERENCE_FASTA \\"
  echo "          [--variant-list VARIANT_TSV]"
  echo ""
  echo "Arguments:"
  echo "  --gene-list      BED file with regions of interest"
  echo "                   /path/to/tab-delimited.bed with 4 fields: chromosome, start, end, gene/locus name; no header line in the BED file"
  echo ""
  echo "  --bam-list       BAM files' paths listed in a text file"
  echo "                   a text file contains /path/to/sample.bam, one per line"
  echo ""
  echo "  --output-dir     Directory to output mpileup and VCF results"
  echo "                   will be created if doesn't exist"
  echo ""
  echo "  --reference      FASTA file of the reference genome"
  echo "                   /path/to/reference.fasta used for BAM files, and is indexed"
  echo ""
  echo "  --variant-list   (optional) TSV file with variants of interest"
  echo "                   /path/to/variants.tsv with 6 tab-delimited fields: Chromosome, Position, Reference, Alternate, dbSNP, Significance; the first line is header"
  echo "                   dbSNP examle: rs2499959771 (put a single dot (.) if no rsID); Significance examples: Pathogenic or Benign"
  echo ""
  echo "Notes:"
  echo "  - Uses samtools (must be in PATH) to scan defined regions (e.g. RNU genes) for mismatches."
  echo "  - Suitable for variant screening of very low-depth/off-target (e.g. RNU4-2) or segmental duplication (e.g. SMN1) regions."
  echo "  - Output VCFs are not realistic, but simplifies interpretation. GT is always infered as 0/1 in this version."
  echo "  - If the variant TSV file is provided, known variants will be annotated. Otherwise variants' singnificance are annotated as Unknown."
  echo "  - Repository: https://github.com/Schahrjar by Shahryar Alavi, s.alavi@ucl.ac.uk"
  echo ""
  echo "  MIT License"
  echo "  Copyright (c) 2025 Shahryar Alavi"
  echo "  Cite this: paper"
  echo ""
  exit 1
}

# -------------------------------
# Parse Arguments
# -------------------------------

variant_tsv=""
if [[ $# -lt 8 ]]; then
  usage
fi

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --gene-list)
      bed_file="$2"
      shift 2
      ;;
    --bam-list)
      listBAMdirs="$2"
      shift 2
      ;;
    --output-dir)
      output_dir="$2"
      shift 2
      ;;
    --reference)
      reference_fasta="$2"
      shift 2
      ;;
    --variant-list)
      variant_tsv="$2"
      shift 2
      ;;
    *)
      echo "❌ Unknown argument: $1"
      usage
      ;;
  esac
done

# -------------------------------
# Create output directories
# -------------------------------

log_file="${output_dir}/screening.log"
vcf_dir="${output_dir}/vcf"
mpileup_dir="${output_dir}/mpileup"

mkdir -p "$output_dir" "$vcf_dir" "$mpileup_dir"

# -------------------------------
# Prepare Variant Lookup File
# -------------------------------

variant_lookup_file=""
has_variant_data="false"

if [[ -n "$variant_tsv" ]]; then
  variant_lookup_file=$(mktemp)
  tail -n +2 "$variant_tsv" > "$variant_lookup_file"
  has_variant_data="true"
fi

# -------------------------------
# Initialize Logging
# -------------------------------

echo -e "\n🕒 Run started at $(date)" | tee "$log_file"

# -------------------------------
# Read BED and BAM Lists
# -------------------------------

mapfile -t regions < <(awk '{print $1":"$2"-"$3"#"$4}' "$bed_file")
mapfile -t bam_files < <(grep -v '^\s*$' "$listBAMdirs" | sed 's/\r//' | sed 's/[[:space:]]*$//')

# -------------------------------
# Main Processing Loop
# -------------------------------

for bam_path in "${bam_files[@]}"; do
  sample_name=$(basename "$bam_path" .bam)
  echo "🔄 Processing sample $sample_name" | tee -a "$log_file"
  vcf_file="${vcf_dir}/${sample_name}.vcf"
  temp_vcf=$(mktemp)
  sample_found_variant=false

  for region_gene in "${regions[@]}"; do
    region="${region_gene%%#*}"
    gene="${region_gene##*#}"
    mpileup_txt="${mpileup_dir}/${sample_name}_${gene}.mpileup.txt"

    if ! samtools mpileup -f "$reference_fasta" -r "$region" "$bam_path" 2>/dev/null > "$mpileup_txt"; then
      continue
    fi

    if ! grep -q '[ACGTNacgtn]' "$mpileup_txt"; then
      rm -f "$mpileup_txt"
      continue
    fi

    awk -v gene="$gene" -v sample="$sample_name" \
        -v varfile="$variant_lookup_file" \
        -v use_variants="$has_variant_data" \
        -v OFS="\t" '
    BEGIN {
      found = 0;
      if (use_variants == "true") {
        while ((getline < varfile) > 0) {
          split($0, F, "\t");
          key = F[1] "_" F[2] "_" F[3] "_" F[4];
          rsids[key] = F[5];
          signs[key] = F[6];
        }
        close(varfile);
      }
    }

    function parse_bases(b, ref,   i, base, len_str, len) {
      delete alts;
      i = 1;
      while (i <= length(b)) {
        base = substr(b, i, 1);
        if (base == "+" || base == "-") {
          len_str = "";
          i++;
          while (i <= length(b) && substr(b, i, 1) ~ /[0-9]/) {
            len_str = len_str substr(b, i, 1);
            i++;
          }
          len = len_str + 0;
          i += len;
        } else if (base ~ /[.,]/) {
          alts[toupper(ref)]++;
          i++;
        } else if (base ~ /[ACGTNacgtn]/) {
          alts[toupper(base)]++;
          i++;
        } else if (base == "*" || base == "#") {
          alts["<DEL>"]++;
          i++;
        } else {
          i++;
        }
      }
      delete alts[toupper(ref)];
    }

    function join(arr, sep,   out, i) {
      out = arr[1];
      for (i = 2; i <= length(arr); i++) out = out sep arr[i];
      return out;
    }

    {
      chrom = $1; pos = $2; ref = toupper($3); dp = $4; bases = $5;
      split("", alt_list); split("", af_list); split("", ad_list); split("", id_list); split("", sig_list);

      parse_bases(bases, ref);

      if (dp > 0) {
        n = 0;
        for (alt in alts) {
          if (alts[alt] > 0) {
            alt_list[++n] = alt;
            ad_list[n] = alts[alt];
            af_list[n] = sprintf("%.3f", alts[alt] / dp);
            key = chrom "_" pos "_" ref "_" alt;
            id_list[n] = (key in rsids) ? rsids[key] : ".";
            sig_list[n] = (key in signs) ? signs[key] : "Unknown";
          }
        }

        if (n > 0) {
          ad_ref = dp;
          for (i = 1; i <= n; i++) ad_ref -= ad_list[i];

          print chrom, pos, join(id_list, ","), ref, join(alt_list, ","), ".", "PASS", \
                "GENE=" gene ";SIGNIFICANCE=" join(sig_list, ","), \
                "GT:AD:DP:AF", "0/1:" ad_ref "," join(ad_list, ",") ":" dp ":" join(af_list, ",") >> "'"$temp_vcf"'";
          found = 1;
        }
      }
    }
    END { exit (found == 1) ? 0 : 1 }
    ' "$mpileup_txt" && sample_found_variant=true || rm -f "$mpileup_txt"
  done

  if $sample_found_variant; then
    {
      echo "##fileformat=VCFv4.2"
      echo "##INFO=<ID=GENE,Number=1,Type=String,Description=\"Gene or locus name\">"
      echo "##INFO=<ID=SIGNIFICANCE,Number=.,Type=String,Description=\"variant significance per ALT allele\">"
      echo "##FORMAT=<ID=GT,Number=1,Type=String,Description=\"Genotype\">"
      echo "##FORMAT=<ID=AD,Number=R,Type=Integer,Description=\"Allele depths for ref and alt\">"
      echo "##FORMAT=<ID=DP,Number=1,Type=Integer,Description=\"Read depth\">"
      echo "##FORMAT=<ID=AF,Number=A,Type=Float,Description=\"Allele fraction (alt/DP)\">"
      echo "##source=RNUscanner.sh"
      echo -e "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\t${sample_name}"
      cat "$temp_vcf"
    } > "$vcf_file"
    echo "   ✅ Saved VCF to $vcf_file" | tee -a "$log_file"
  else
    echo "   ⚠️  No mismatches found in $sample_name" | tee -a "$log_file"
  fi

  rm -f "$temp_vcf"
done

# -------------------------------
# Done
# -------------------------------

echo -e "\n✅ All regions scanned for all BAMs at $(date)" | tee -a "$log_file"

# Cleanup
[[ -n "$variant_lookup_file" ]] && rm -f "$variant_lookup_file"
