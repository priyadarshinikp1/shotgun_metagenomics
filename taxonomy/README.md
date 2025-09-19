---

# Metagenomic Taxonomic Profiling Pipeline

This repository contains a Bash pipeline script for metagenomic data processing and taxonomic profiling. It automates quality control, host read removal, taxonomic classification, abundance estimation, and visualization.

---

## Requirements

* **Installed software**

  * [FastQC](https://www.bioinformatics.babraham.ac.uk/projects/fastqc/)
  * [fastp](https://github.com/OpenGene/fastp)
  * [MultiQC](https://multiqc.info/)
  * [KneadData](https://github.com/biobakery/kneaddata)
  * [Kraken2](https://ccb.jhu.edu/software/kraken2/)
  * [Bracken](https://ccb.jhu.edu/software/bracken/)
  * [KronaTools](https://github.com/marbl/Krona/wiki)
  * Standard Linux tools (`bash`, `wget`, `tar`, etc.)

* **Configuration file**
  The script expects an environment file, e.g.:

  ```bash
  # gut/config.env.save
---

## How it Works

1. **Database setup**

   * Downloads KneadData database if missing
   * Downloads Kraken2 database if missing
   * Builds Bracken database files

2. **Quality Control**

   * FastQC on raw reads
   * Read trimming with fastp
   * FastQC on cleaned reads
   * MultiQC summary report

3. **Host read removal**

   * Uses KneadData to filter host sequences

4. **Taxonomic classification**

   * Classifies reads with Kraken2
   * Generates `.kraken2.out` and `.kraken2.report`

5. **Abundance estimation**

   * Estimates species-level abundances with Bracken

6. **Visualization**

   * Generates interactive Krona plots

---

## Usage

Run normally:

```bash
bash run_taxonomy_pipeline.sh
```

Resume mode (skips completed steps if flag + outputs exist):

```bash
bash run_taxonomy_pipeline.sh --resume
```

Logs are written to:

```
pipeline_runtime.log
```

---

## Input / Output

* **Inputs:**

  * Paired FASTQ files: `$READ1`, `$READ2`
  * Databases: KneadData DB, Kraken2 DB (downloaded if missing)

* **Outputs (in \$OUTPUT\_DIR):**

  * `*_fastqc.html / .zip` → FastQC reports
  * `*_R1.clean.fastq.gz / *_R2.clean.fastq.gz` → trimmed reads
  * `*_fastp.html / .json` → fastp reports
  * `*_multiqc_report.html` → MultiQC summary
  * `kneaddata_cleaned/` → host-removed reads
  * `*.kraken2.out / *.kraken2.report` → Kraken2 results
  * `*.bracken.species` → Bracken species abundance estimates
  * `*.krona.html` → Krona interactive visualization

---

## Notes

* **RESUME mode** requires both:

  * A `.done` flag file in `$OUTPUT_DIR`, and
  * The expected output files.
    If outputs are missing, the step is re-run.

* Adjust `$THREADS` in your config for better performance.

---

Do you want me to also **add an example workflow diagram** (like a flowchart figure) to this README so new users can quickly visualize the pipeline?
