---

# HUMAnN3 Functional Profiling Pipeline

This repository contains a Bash pipeline script for running **HUMAnN3** on preprocessed metagenomic reads. It automates database setup, read merging, parallelized HUMAnN3 runs, and post-processing.

---

## Requirements

* **Installed software**

  * [HUMAnN3](https://github.com/biobakery/humann)
  * [KneadData](https://github.com/biobakery/kneaddata) (already run before using this script)
  * [GNU Parallel](https://www.gnu.org/software/parallel/)
  * Standard Linux tools (`bash`, `zcat`, `mkdir`)

* **Configuration file**
  The script expects an environment config file at:

  ```
  ~/gut/h3_config.env
  ```
---

## How it Works

1. **Database setup**
   Downloads ChocoPhlAn and UniRef databases if missing and updates HUMAnN3 config.

2. **Read merging**
   For each sample in `$KNEADDATA_DIR`, merges paired reads:

   ```
   *_paired_1.fastq.gz + *_paired_2.fastq.gz → *_merged.fastq
   ```

3. **Parallel HUMAnN3 run**
   Runs HUMAnN3 on merged reads using multiple threads and samples in parallel.

4. **Post-processing**

   * Joins gene family and pathway tables across samples
   * Renormalizes outputs into CPM and relative abundance

---

## Usage

Run normally:

```bash
bash run_humann3.sh
```

Resume mode (skips steps if output files already exist):

```bash
bash run_humann3.sh --resume
```

Logs are written to:

```
$HUMANN_OUT/humann_runtime.log
```

---

## Input / Output

* **Inputs:**
  Preprocessed paired FASTQ files from KneadData in `$KNEADDATA_DIR`, named like:

  ```
  sample1_paired_1.fastq.gz
  sample1_paired_2.fastq.gz
  ```

* **Outputs:**
  In `$HUMANN_OUT`:

  * Per-sample HUMAnN3 results (`*_genefamilies.tsv`, `*_pathabundance.tsv`, etc.)
  * Joined and normalized tables:

    * `genefamilies.tsv`
    * `genefamilies_cpm.tsv`
    * `pathabundance.tsv`
    * `pathabundance_relab.tsv`

---


Would you like me to **extend this README with an example `samples.csv` format and instructions** for how we could modify the script to use it? That way others in your team can choose either approach.
