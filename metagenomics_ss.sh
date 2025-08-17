#!/bin/bash
set -euo pipefail

# Load configuration
source config.env
source ~/miniconda3/etc/profile.d/conda.sh
# Activate conda environment
conda activate metagenomics_env

# === DATABASE SETUP ===

# Kneaddata DB
if [ ! -d "$KNEADDATA_DB" ]; then
    echo "[INFO] Kneaddata DB not found. Downloading $KNEADDATA_DB_TYPE..."
    mkdir -p "$(dirname "$KNEADDATA_DB")"
    kneaddata_database \
      --download "$KNEADDATA_DB_TYPE" bowtie2 "$(dirname "$KNEADDATA_DB")"
fi

# Kraken2 DB
if [ ! -d "$KRAKEN2_DB" ]; then
    echo "[INFO] Kraken2 DB not found. Downloading from $KRAKEN2_DB_URL..."
    mkdir -p "$(dirname "$KRAKEN2_DB")"
    wget "$KRAKEN2_DB_URL" -O /tmp/k2_db.tgz
    tar -xvzf /tmp/k2_db.tgz -C "$(dirname "$KRAKEN2_DB")/.."
fi

# Bracken DB build
if [ ! -f "$KRAKEN2_DB/database${BRACKEN_READ_LEN}mers.kmer_distrib" ]; then
    echo "[INFO] Bracken DB files not found. Building..."
    bracken-build \
      -d "$KRAKEN2_DB" \
      -t "$THREADS" \
      -k "$BRACKEN_KMER" \
      -l "$BRACKEN_READ_LEN"
fi

# === QC ===
fastqc "$READ1" "$READ2"

fastp \
  -i "$READ1" \
  -I "$READ2" \
  -o reads_R1.clean.fastq.gz \
  -O reads_R2.clean.fastq.gz \
  --detect_adapter_for_pe \
  --cut_front --cut_tail --cut_mean_quality 20 \
  --length_required 50 \
  --trim_poly_g \
  --thread "$THREADS" \
  --html fastp_report.html \
  --json fastp_report.json

fastqc reads_R1.clean.fastq.gz reads_R2.clean.fastq.gz
multiqc .

# === Host removal ===
kneaddata \
  -i1 reads_R1.clean.fastq.gz \
  -i2 reads_R2.clean.fastq.gz \
  -db "$KNEADDATA_DB" \
  -o kneaddata_cleaned \
  -t "$THREADS"

# === Taxonomic classification ===
kraken2 \
  --db "$KRAKEN2_DB" \
  --threads "$THREADS" \
  --paired kneaddata_cleaned/*_R1_* kneaddata_cleaned/*_R2_* \
  --report sample.kraken2.report \
  --output sample.kraken2.out

bracken \
  -d "$KRAKEN2_DB" \
  -i sample.kraken2.report \
  -o sample.bracken.species \
  -r "$BRACKEN_READ_LEN" -l S

# === Visualization ===
cut -f2,3 sample.kraken2.out > sample.krona.input
ktImportTaxonomy sample.krona.input -o sample.krona.html

echo "[INFO] Pipeline completed successfully."
