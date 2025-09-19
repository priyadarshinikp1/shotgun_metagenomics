---

# Shotgun Metagenomics Analysis Pipeline

This repository contains a **comprehensive pipeline for shotgun metagenomic analysis**, including quality control, taxonomic classification, functional profiling.

---

## Features

* **Environment management**

  * Reproducible installation via `environment.yml`

* **Pipelines**

  * **QC + Taxonomy pipeline**

    * FastQC, fastp, KneadData, Kraken2, Bracken, Krona
  * **Functional profiling pipeline**

    * HUMAnN3 (ChocoPhlAn + UniRef databases), table joining, normalization

* **Analysis notebook**

  * Jupyter notebook with step-by-step explanation, visualizations

---

## Setup

1. **Clone this repository**

   ```bash
   git clone https://github.com/your-username/shotgun-metagenomics.git
   cd shotgun-metagenomics
   ```

2. **Create the environment**

   ```bash
   conda env create -f metagenomics_env.yml
   conda activate metagenomics_env
   ```

3. **Configure paths and parameters**
   Edit the configuration file(s):

   * `gut/config.env.save` → for QC + taxonomy pipeline
   * `gut/h3_config.env` → for HUMAnN3 functional profiling

---

## Pipelines

### 1. QC + Taxonomy (Kraken2/Bracken/Krona)

```bash
bash run_taxonomy_pipeline.sh
```

Resume mode (skips completed steps):

```bash
bash run_taxonomy_pipeline.sh --resume
```

**Outputs:**

* Cleaned reads (FastQC + fastp + KneadData)
* Kraken2 classification reports
* Bracken species abundances
* Krona interactive plots

---

### 2. Functional Profiling (HUMAnN3)

```bash
bash functional.sh
```

Resume mode:

```bash
bash functional.sh --resume
```

**Outputs:**

* Per-sample gene family and pathway abundances
* Joined and normalized tables:

  * `genefamilies.tsv`, `genefamilies_cpm.tsv`
  * `pathabundance.tsv`, `pathabundance_relab.tsv`

---

## Jupyter Notebook

The `notebooks/` folder contains a **Jupyter notebook** with:

* Overview of the shotgun metagenomics workflow
* Code to load and visualize Kraken2/Bracken/HUMAnN3 outputs

---

## Input / Output Overview

* **Inputs:**

  * Raw paired-end FASTQ files (`*_R1.fastq.gz`, `*_R2.fastq.gz`)
  * Reference databases (downloaded automatically if missing)

* **Outputs:**

  * QC reports (FastQC, fastp, MultiQC)
  * Host-filtered reads (KneadData)
  * Taxonomic profiles (Kraken2, Bracken, Krona)
  * Functional profiles (HUMAnN3 tables)
  * Figures and summaries (from Jupyter notebooks)

---

## Notes

* Ensure enough disk space for large databases (Kraken2, HUMAnN3).
* Use `--resume` to skip previously completed steps.
* All logs are timestamped and written to the pipeline runtime log files.

---
