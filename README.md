# RNUscanner
A tool for mass screening RNU genes for significant variants. These RNA genes have been discovered to cause neurodevelopmental disorders but they are not covered in exome sequencings. However, there is a chance of off-target reads which RNUscanner captures by getting BAM files and returning any mismatches, even the low quality ones. It outputs per-sample VCF files and optionally annotates known variants.

*The goal is to benefit the most from a huge amount of exome data, as many genetic patients have nothing availabe except an exome data, awaiting for diagnosis.*

## 🔧 Features
- Mainly for RNU genes, but applicable for any regions of interest
- Works on any genome assembly (e.g. hg38 or hg19)
- Requires Bash (Linux/Mac), `bcftools`, and `samtools`
- Doesn't call deletions supported by a single sequence read.

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
It scans dozens of exomes per minute. To quickly screen results for samples having known pathogenic variants (assuming that VCF annotation is enabled, explained below) users could then run:

```bash
grep -i "Pathogenic" -r OUTPUT_DIR/*.vcf
```

Good luck with your screening!

## 🗂️ Inputs
* **BED_FILE**
is a tab-delimited file with 4 fields: chromosome, start, end, and gene/locus name. BED file doesn't have header line. Genome coordinates should be in consistance with the BAM file (and the reference genome, below). Example locus:
```txt
chr12	120291825	120291842	RNU4-2
```
A list of constraint regions of 4 RNU genes (RNU2-2, RNU4-2, RNU5A-1, and RNU5B-1) is provided in the RNUscanner examples folder.

* **BAM_LIST_FILE**
is a text file lists multiple ```/path/to/sample.bam```, one BAM file path per line.

* **REFERENCE_FASTA**
is the ```GENOME.fasta``` (or ```GENOME.fa```) file that has been used for raw sequence reads alignment (the reference assembly of BAM files). The reference file must be indexed.

* **VARIANT_VCF** (optional) is a list of known variants in VCF format to annotate detected variants. Example VCF:
```txt
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
It is encouraged to keep the VCF information and header lines as the same. Chromosomes which their variants are added to the VCF should be added to the information (e.g ```##contig=<ID=chr11,length=135086622,dbSNP_version=157>``` if adding RNU2-2 variants). For a complete list of clinical RNU genes' variants, see RNUscanner examples folder.

* **OUTPUT_DIR**
(optional) is the directory name where outputs are saved. This will be created if doesn't exits.

* **SAMTOOLS**
(optional) is the path to `samtools` executable file. Old versions may not work.

* **BCFTOOLS**
(optional) is the path to `bcftools` executable file. Old versions may not work.

## 📜 Citation

This tool is released prior to our manuscript submission to assist researchers and clinicians in their diagnostics. You may contact [Shahryar Alavi](https://schahrjar.github.io/) if you use RNUscanner for your publication.

MIT License | Copyright &copy; 2025 Shahryar Alavi
