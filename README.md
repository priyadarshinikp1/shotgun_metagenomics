# Shotgun Metagenomics Pipeline

This repository contains a reproducible workflow for **shotgun metagenomic data analysis**, from raw sequencing reads to statistical analysis and visualization.  

The pipeline integrates commonly used tools for **quality control, host read removal, taxonomic classification, abundance estimation, and downstream analysis**.

---

## Workflow Overview
1. **Quality Control**  
   - [`FastQC`](https://www.bioinformatics.babraham.ac.uk/projects/fastqc/)  
   - [`fastp`](https://github.com/OpenGene/fastp)  
   - [`MultiQC`](https://multiqc.info/)

2. **Removal of Host Contamination**  
   - [`kneaddata`](https://huttenhower.sph.harvard.edu/kneaddata/) OR  
   - [`bowtie2`](http://bowtie-bio.sourceforge.net/bowtie2/) + [`samtools`](http://www.htslib.org/)

3. **Taxonomic Classification**  
   - [`Kraken2`](https://ccb.jhu.edu/software/kraken2/)  
   - [`Bracken`](https://ccb.jhu.edu/software/bracken/)

4. **Abundance Estimation**  
   - Merge Bracken reports across samples into a single abundance table

5. **Statistical Analysis & Visualization**  
   - [`phyloseq`](https://joey711.github.io/phyloseq/)  
   - [`vegan`](https://cran.r-project.org/web/packages/vegan/index.html)  
   - [`DESeq2`](https://bioconductor.org/packages/release/bioc/html/DESeq2.html)  
   - [`Krona`](https://github.com/marbl/Krona)

---

---

## ⚙️ Installation

It is recommended to use **conda** environments for tool management.

Example (Kraken2 + Bracken environment):
```bash
conda create -n kraken2_env -c bioconda -c conda-forge kraken2 bracken
conda activate kraken2_env


## **Outputs:**

QC reports (fastp_report.html, multiqc_report.html)

Host-filtered FASTQ files

Taxonomy classification (sample.kraken2.report, sample.bracken.species)

Abundance tables (merged_abundance.tsv)

Statistical results (alpha_diversity.tsv, beta_diversity.pdf, differential_abundance.tsv)

