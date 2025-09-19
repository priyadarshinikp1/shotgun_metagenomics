
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

# === Hybrid run_step function ===
run_step() {
    local step_name="$1"
    local flag_file="$2"
    local outputs="$3"
    shift 3

    if $RESUME && [ -f "$flag_file" ]; then
        local all_exist=true
        for f in $outputs; do
            if [ ! -e "$f" ]; then
                all_exist=false
                break
            fi
        done
        if $all_exist; then
            echo "[INFO] Skipping $step_name (flag + outputs exist)" | tee -a "$LOGFILE"
            echo "" | tee -a "$LOGFILE"
            return 0
        else
            echo "[WARN] Flag exists but outputs missing → re-running $step_name" | tee -a "$LOGFILE"
        fi
    fi

    echo "[INFO] Starting: $step_name" | tee -a "$LOGFILE"
    local start_time
    start_time=$(date +%s)

    if "$@"; then
        local end_time runtime
        end_time=$(date +%s)
        runtime=$((end_time - start_time))
        echo "[INFO] $step_name complete (took ${runtime}s)" | tee -a "$LOGFILE"
        touch "$flag_file"
    else
        echo "[ERROR] $step_name failed at $(date)" | tee -a "$LOGFILE"
        exit 1
    fi

    echo "" | tee -a "$LOGFILE"
}

# === Load configuration ===
source gut/config.env.save
source ~/miniconda3/etc/profile.d/conda.sh
#conda activate

mkdir -p "$OUTPUT_DIR"

# === Database setup ===
run_step "Database setup" "$OUTPUT_DIR/db_setup.done" "$KRAKEN2_DB" bash -c "
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
run_step "FastQC raw reads" "$OUTPUT_DIR/fastqc_raw.done" \
    "$OUTPUT_DIR/$(basename $READ1 .fastq.gz)_fastqc.html \
     $OUTPUT_DIR/$(basename $READ2 .fastq.gz)_fastqc.html \
     $OUTPUT_DIR/$(basename $READ1 .fastq.gz)_fastqc.zip \
     $OUTPUT_DIR/$(basename $READ2 .fastq.gz)_fastqc.zip" \
    fastqc -o "$OUTPUT_DIR" --threads "$THREADS" $READ1 $READ2


run_step "Read trimming with fastp" "$OUTPUT_DIR/fastp.done" \
    "$OUTPUT_DIR/${OUTPUT_PREFIX}_R1.clean.fastq.gz $OUTPUT_DIR/${OUTPUT_PREFIX}_R2.clean.fastq.gz" \
    fastp \
    -i $READ1 \
    -I $READ2 \
    -o "$OUTPUT_DIR/${OUTPUT_PREFIX}_R1.clean.fastq.gz" \
    -O "$OUTPUT_DIR/${OUTPUT_PREFIX}_R2.clean.fastq.gz" \
    --detect_adapter_for_pe \
    --cut_front --cut_tail --cut_mean_quality 20 \
    --length_required 50 \
    --trim_poly_g \
    --thread "$THREADS" \
    --html "$OUTPUT_DIR/${OUTPUT_PREFIX}_fastp.html" \
    --json "$OUTPUT_DIR/${OUTPUT_PREFIX}_fastp.json"

run_step "FastQC cleaned reads" "$OUTPUT_DIR/fastqc_clean.done" \
    "$OUTPUT_DIR/${OUTPUT_PREFIX}_R1.clean_fastqc.html $OUTPUT_DIR/${OUTPUT_PREFIX}_R2.clean_fastqc.html" \
    fastqc -o "$OUTPUT_DIR" \
    "$OUTPUT_DIR/${OUTPUT_PREFIX}_R1.clean.fastq.gz" \
    "$OUTPUT_DIR/${OUTPUT_PREFIX}_R2.clean.fastq.gz"

run_step "MultiQC report" "$OUTPUT_DIR/multiqc.done" \
    "$OUTPUT_DIR/${OUTPUT_PREFIX}_multiqc_report.html" \
    multiqc "$OUTPUT_DIR" -o "$OUTPUT_DIR" -n "${OUTPUT_PREFIX}_multiqc_report.html" --force

mkdir -p "$OUTPUT_DIR/kneaddata_cleaned"

# === Host read removal (paired only) ===
run_step "Kneaddata host removal" "$OUTPUT_DIR/kneaddata.done" \
    "$OUTPUT_DIR/kneaddata_cleaned/${OUTPUT_PREFIX}_cleaned_paired_1.fastq $OUTPUT_DIR/kneaddata_cleaned/${OUTPUT_PREFIX}_cleaned_paired_2.fastq" \
    kneaddata \
    -i1 "$OUTPUT_DIR/${OUTPUT_PREFIX}_R1.clean.fastq.gz" \
    -i2 "$OUTPUT_DIR/${OUTPUT_PREFIX}_R2.clean.fastq.gz" \
    -db "$KNEADDATA_DB" \
    -o "$OUTPUT_DIR/kneaddata_cleaned" \
    -t "$THREADS" \
    --output-prefix "${OUTPUT_PREFIX}_cleaned"


# === Taxonomic classification ===
run_step "Taxonomic classification" "$OUTPUT_DIR/kraken2.done" \
    "$OUTPUT_DIR/${OUTPUT_PREFIX}.kraken2.out $OUTPUT_DIR/${OUTPUT_PREFIX}.kraken2.report" \
    kraken2 \
    --db "$KRAKEN2_DB" \
    --threads "$THREADS" \
    --paired "$OUTPUT_DIR/kneaddata_cleaned/${OUTPUT_PREFIX}_cleaned_paired_1.fastq" \
            "$OUTPUT_DIR/kneaddata_cleaned/${OUTPUT_PREFIX}_cleaned_paired_2.fastq" \
    --report "$OUTPUT_DIR/${OUTPUT_PREFIX}.kraken2.report" \
    --output "$OUTPUT_DIR/${OUTPUT_PREFIX}.kraken2.out"

# === Abundance estimation ===
run_step "Abundance estimation" "$OUTPUT_DIR/bracken.done" \
    "$OUTPUT_DIR/${OUTPUT_PREFIX}.bracken.species" \
    bracken \
    -d "$KRAKEN2_DB" \
    -i "$OUTPUT_DIR/${OUTPUT_PREFIX}.kraken2.report" \
    -o "$OUTPUT_DIR/${OUTPUT_PREFIX}.bracken.species" \
    -r "$BRACKEN_READ_LEN" -l S

# === Visualization (Krona) ===
run_step "Visualization" "$OUTPUT_DIR/krona.done" \
    "$OUTPUT_DIR/${OUTPUT_PREFIX}.krona.html" \
    bash -c "
KRONA_DIR=\$(dirname \$(which ktImportTaxonomy))/../opt/krona
if [ -d \"\$KRONA_DIR\" ] && [ ! -d \"\$KRONA_DIR/taxonomy\" ]; then
    echo \"[INFO] Krona taxonomy DB not found. Running ktUpdateTaxonomy.sh...\"
    ktUpdateTaxonomy.sh
fi
cut -f2,3 \"$OUTPUT_DIR/${OUTPUT_PREFIX}.kraken2.out\" > \"$OUTPUT_DIR/${OUTPUT_PREFIX}.krona.input\"
ktImportTaxonomy \"$OUTPUT_DIR/${OUTPUT_PREFIX}.krona.input\" -o \"$OUTPUT_DIR/${OUTPUT_PREFIX}.krona.html\"
"

echo "[INFO] Pipeline completed successfully at $(date)" | tee -a "$LOGFILE"
