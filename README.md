[![GitHub release](https://img.shields.io/github/v/release/Schahrjar/RNUscanner)](https://github.com/Schahrjar/RNUscanner/releases/latest)
[![last commit](https://img.shields.io/github/last-commit/Schahrjar/RNUscanner)](https://github.com/Schahrjar/RNUscanner/commits/main)

# RNUscanner
The tool screens for any mismatches in sequence reads at a given genomic region.

Small nuclear RNA genes' mutations cause neurodevelopmental disorders, but they are not covered in exome enrichments. RNUscanner captures off-target reads from BAM files and returns VCF files if any variant is detected, even the low quality ones, and optionally annotates known variants.

> [!NOTE]
> *The goal is to benefit the most from a huge amount of exome data, as many genetic patients have nothing available except an exome data, awaiting for diagnosis.*

## 🔧 Features
- Mainly for RNU genes, but applicable for any regions of interest
- Calls any mismatches, even those supported by a single sequence read
- Works on any genome assembly (e.g. hg38 or hg19)
- Requires Bash (Linux/Mac), `bcftools`, and `samtools`

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
  --gene-list <BED_FILE> \
  --bam-list <BAM_LIST_FILE> \
  --reference <REFERENCE_FASTA> \
  [--variant-annotation <VARIANT_VCF>] \
  [--output-dir <OUTPUT_DIR>] \
  [--samtools-path <SAMTOOLS>] \
  [--bcftools-path <BCFTOOLS>]
```
It scans dozens of exomes per minute on a regular machine.

> [!TIP]
> To quickly list samples harbouring known pathogenic variants (assuming that VCF annotation is enabled; explained below) users can then run:
> ```bash
> grep -i "Pathogenic" -r RNUscanner_out/*.vcf
> ```

Good luck with your screening!

## 🗂️ Inputs
### Mandatory
* **BED_FILE**
is a tab-delimited file with 4 fields: chromosome, start, end, and gene/locus name. BED file doesn't have header line. Genome coordinates should be in consistance with the BAM file (and the reference genome, see below). Example locus:
```txt
chr12	120291825	120291842	RNU4-2
```
A list of constraint regions of 4 RNU genes (RNU2-2, RNU4-2, RNU5A-1, and RNU5B-1) is provided in the RNUscanner `example_data/RNU-loci.bed` file (based on hg38).

* **BAM_LIST_FILE**
is a text file lists multiple `/path/to/sample.bam` paths, one BAM file path per line. Assuming that all of the desired BAM files are in the `/path/to/` directory (or its subdirectories), users could use this line of code to create a list of BAM files' paths:
```bash
find /path/to/ -type f -iname *.bam > BAM_LIST_FILE.txt
```

* **REFERENCE_FASTA**
is the `*.fasta` (or `*.fa`) file that has been used for raw sequence reads alignment (i.e. the reference assembly of BAM files). The reference file must be indexed.

### Optional
* **VARIANT_VCF**
is a list of known variants in VCF format to annotate detected variants. Annotation is enabled if this VCF file is provided (default is disabled). Example VCF:
```vcf
##fileformat=VCFv4.2
##fileDate=20250611
##reference=hg38
##contig=<ID=chr12,length=133275309,dbSNP_version=157>
##contig=<ID=chr15,length=101991189,dbSNP_version=157>
##FILTER=<ID=PASS,Description="All filters passed">
##INFO=<ID=GENE,Number=1,Type=String,Description="Gene or locus name">
##INFO=<ID=SIGNIFICANCE,Number=1,Type=String,Description="Variant significance">
##source=RNUscanner
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO
chr12	120291839	rs2499959771	T	TA	.	PASS	GENE=RNU4-2;SIGNIFICANCE=Pathogenic
chr15	65304715	.	C	G	.	PASS	GENE=RNU5B-1;SIGNIFICANCE=LikelyPathogenic
```
Information of chromosomes which their variants are added to the VCF should be added to the VCF information line (e.g. add `##contig=<ID=chr11,length=135086622,dbSNP_version=157>` if putting RNU2-2 variants in). For a complete list of clinical RNU genes' variants, users could use RNUscanner `example_data/RNU-clinical-variants.vcf` file (based on hg38).

> [!WARNING]
> It is encouraged to keep the VCF information and header lines as explained to avoid annotation failure.

* **OUTPUT_DIR**
is the directory name where outputs will be saved, with the `RNUscanner_out` as its default. The directory will be created if it doesn't exist.

* **SAMTOOLS**
is the path to `samtools` executable file, otherwise it will be assumed that `samtools` is in the PATH (requires `samtools` version 1.14+).

* **BCFTOOLS**
is the path to `bcftools` executable file, otherwise it will be assumed that `bcftools` is in the PATH (requires `bcftools` version 1.19+).

## 📜 Citation

This tool is released prior to our manuscript submission to assist researchers and clinicians in their diagnostics. You may contact [Shahryar Alavi](https://schahrjar.github.io/) if you use RNUscanner in your publication.
