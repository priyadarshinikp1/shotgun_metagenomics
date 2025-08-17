#!/bin/bash
set -euo pipefail

LOGFILE="pipeline_runtime.log"
RESUME=false

# === Parse arguments ===
for arg in "$@"; do
    case $arg in
        --resume)
            RESUME=true
            echo "[INFO] Running in RESUME mode (skipping completed steps)"
            ;;
        *)
            echo "[WARN] Unknown argument: $arg"
            ;;
    esac
done

echo "=== Pipeline run started at $(date) ===" >> "$LOGFILE"

# === Helper function for timing and logging ===
run_step() {
    local step_name="$1"
    local output_files="$2"
    shift 2

    # Skip if output exists and RESUME mode is on
    if $RESUME && [ -e "$output_files" ]; then
        echo "[INFO] Skipping $step_name (found $output_files)" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"
        return 0
    fi

    echo "[INFO] Starting: $step_name" | tee -a "$LOGFILE"
    local start_time
    start_time=$(date +%s)

    if "$@"; then
        local end_time runtime
        end_time=$(date +%s)
        runtime=$((end_time - start_time))
        echo "[INFO] $step_name complete (took ${runtime}s)" | tee -a "$LOGFILE"
    else
        echo "[ERROR] $step_name failed at $(date)" | tee -a "$LOGFILE"
        exit 1
    fi

    echo "" | tee -a "$LOGFILE"
}

# === Load configuration ===
source config.env
source ~/miniconda3/etc/profile.d/conda.sh
conda activate metagenomics_env

# === Database setup ===
run_step "Database setup" "$KRAKEN2_DB" bash -c "
if [ ! -d \"$KNEADDATA_DB\" ]; then
    echo \"[INFO] Kneaddata DB not found. Downloading $KNEADDATA_DB_TYPE...\"
    mkdir -p \"\$(dirname \"$KNEADDATA_DB\")\"
    kneaddata_database --download \"$KNEADDATA_DB_TYPE\" bowtie2 \"\$(dirname \"$KNEADDATA_DB\")\"
fi

if [ ! -d \"$KRAKEN2_DB\" ]; then
    echo \"[INFO] Kraken2 DB not found. Downloading from $KRAKEN2_DB_URL...\"
    mkdir -p \"\$(dirname \"$KRAKEN2_DB\")\"
    wget \"$KRAKEN2_DB_URL\" -O /tmp/k2_db.tgz
    tar -xvzf /tmp/k2_db.tgz -C \"\$(dirname \"$KRAKEN2_DB\")/..\"
fi

if [ ! -f \"$KRAKEN2_DB/database${BRACKEN_READ_LEN}mers.kmer_distrib\" ]; then
    echo \"[INFO] Bracken DB files not found. Building...\"
    bracken-build -d \"$KRAKEN2_DB\" -t \"$THREADS\" -k \"$BRACKEN_KMER\" -l \"$BRACKEN_READ_LEN\"
fi
"

# === Quality Control (QC) ===
run_step "FastQC raw reads" "fastqc_done.flag" fastqc "$READ1" "$READ2" && touch fastqc_done.flag

run_step "Read trimming with fastp" "reads_R1.clean.fastq.gz" fastp \
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

run_step "FastQC cleaned reads" "fastqc_clean_done.flag" fastqc reads_R1.clean.fastq.gz reads_R2.clean.fastq.gz && touch fastqc_clean_done.flag

run_step "MultiQC report" "multiqc_report_done.flag" multiqc . && touch multiqc_report_done.flag

# === Host read removal ===
run_step "Kneaddata host removal" "kneaddata_cleaned/reads_R1.clean.fastq.gz" kneaddata \
    -i1 reads_R1.clean.fastq.gz \
    -i2 reads_R2.clean.fastq.gz \
    -db "$KNEADDATA_DB" \
    -o kneaddata_cleaned \
    -t "$THREADS"

# === Taxonomic classification ===
run_step "Taxonomic classification" "sample.kraken2.out" kraken2 \
    --db "$KRAKEN2_DB" \
    --threads "$THREADS" \
    --paired kneaddata_cleaned/reads_R1.clean.fastq.gz kneaddata_cleaned/reads_R2.clean.fastq.gz \
    --report sample.kraken2.report \
    --output sample.kraken2.out

# === Abundance estimation ===
run_step "Abundance estimation" "sample.bracken.species" bracken \
    -d "$KRAKEN2_DB" \
    -i sample.kraken2.report \
    -o sample.bracken.species \
    -r "$BRACKEN_READ_LEN" -l S

# === Visualization (Krona) ===
run_step "Visualization" "sample.krona.html" bash -c "
KRONA_DIR=\$(dirname \$(which ktImportTaxonomy))/../opt/krona
if [ -d \"\$KRONA_DIR\" ] && [ ! -d \"\$KRONA_DIR/taxonomy\" ]; then
    echo \"[INFO] Krona taxonomy DB not found. Running ktUpdateTaxonomy.sh...\"
    ktUpdateTaxonomy.sh
fi
cut -f2,3 sample.kraken2.out > sample.krona.input
ktImportTaxonomy sample.krona.input -o sample.krona.html
"

echo "[INFO] Pipeline completed successfully at $(date)" | tee -a "$LOGFILE"
