# RNUscanner
The tool scans off-target regions from exome BAM files to detect clinically relevant mismatches. It outputs per-sample low-stringency VCF files and optionally annotates known variants.

## 🔧 Features
- Mainly for RNU genes, but applicable for any regions of interest
- Outputs allele depths and fractions in VCF format
- Annotates using user-provided TSV, containing dbSNP and clinical significance info.
- Works on any genome assembly (e.g. hg38 or hg19)
- Requires Bash (Linux/Mac) and `samtools`

## 📦 Usage

Clone the repository:

```bash
git clone https://github.com/Schahrjar/RNUscanner.git
cd RNUscanner
chmod +x RNUscanner.sh
```
Then run RNUscanner:
```bash
./RNUscanner.sh \
  --gene-list BED_FILE \
  --bam-list BAM_LIST_FILE \
  --output-dir OUTPUT_DIR \
  --reference REFERENCE_FASTA \
  [--variant-list VARIANT_TSV]
```
**BED_FILE** is a tab-delimited file with 4 fields: chromosome, start, end, and gene/locus name. BED file doesn't have header line. Genome coordinates should be in consistance with the BAM file (and the reference genome, below).

**BAM_LIST_FILE** is a text file lists /path/to/sample.bam, one BAM file per line.

**OUTPUT_DIR** is the directory name where outputs are saved. This will be created if doesn't exits.

**REFERENCE_FASTA** is the .fasta (or .fa) file that has been used for raw sequence reads alignment (the reference assembly of BAM files). The reference file must be indexed.

**VARIANT_TSV** is an optional file for annotation of detected variants. This is a tab-delimited file with 6 columns: Chromosome, Position, Reference, Alternate, dbSNP, and Significance. First line of the TSV file is the header.

## 📜 Citation

This tool is released prior to our manuscript submission to assist researchers and clinicians in their diagnostics. Please contact [Shahryar Alavi](https://schahrjar.github.io/) if you use RNUscanner for your publication.
