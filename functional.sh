#!/bin/bash
set -euo pipefail

# === Load config ===
source ~/gut/h3_config.env

LOGFILE="$HUMANN_OUT/humann_runtime.log"
RESUME=false

# Parse command-line arguments
for arg in "$@"; do
    case $arg in
        --resume) RESUME=true ;;
    esac
done

echo "=== HUMAnN3 pipeline started at $(date) ===" >> "$LOGFILE"

run_step() {
    step_name=$1
    output_files=$2
    shift 2

    if $RESUME; then
        skip=true
        for file in $output_files; do
            if [ ! -e "$file" ]; then
                skip=false
                break
            fi
        done
        if $skip; then
            echo "[INFO] Skipping $step_name (all output files exist)" | tee -a "$LOGFILE"
            return 0
        fi
    fi

    echo "[INFO] Starting: $step_name" | tee -a "$LOGFILE"
    start_time=$(date +%s)

    if "$@"; then
        end_time=$(date +%s)
        runtime=$((end_time - start_time))
        echo "[INFO] $step_name complete (took ${runtime}s)" | tee -a "$LOGFILE"
    else
        echo "[ERROR] $step_name failed at $(date)" | tee -a "$LOGFILE"
        exit 1
    fi
    echo "" | tee -a "$LOGFILE"
}

# === Create directories ===
mkdir -p "$HUMANN_CHOCO_DB" "$HUMANN_UNIREF_DB" "$HUMANN_DB_DIR" "$HUMANN_OUT/merged_reads"
MERGED_READS_DIR="$HUMANN_OUT/merged_reads"

# === HUMAnN database setup ===
run_step "HUMAnN database setup" "$HUMANN_CHOCO_DB $HUMANN_UNIREF_DB" bash -c "
if [ -z \"\$(ls -A \"$HUMANN_CHOCO_DB\")\" ]; then
    humann_databases --download chocophlan full \"$HUMANN_CHOCO_DB\"
fi
if [ -z \"\$(ls -A \"$HUMANN_UNIREF_DB\")\" ]; then
    humann_databases --download uniref \"$HUMANN_UNIREF_TYPE\" \"$HUMANN_UNIREF_DB\"
fi
humann_config --update database_folders nucleotide \"$HUMANN_CHOCO_DB\"
humann_config --update database_folders protein \"$HUMANN_UNIREF_DB\"
"

# === Merge KneadData paired reads ===
for R1 in "$KNEADDATA_DIR"/*_paired_1.fastq.gz; do
    SAMPLE_ID=$(basename "$R1" "_paired_1.fastq.gz")
    R2="${R1/_paired_1.fastq.gz/_paired_2.fastq.gz}"
    MERGED="$MERGED_READS_DIR/${SAMPLE_ID}_merged.fastq"

    run_step "Merge $SAMPLE_ID paired reads" "$MERGED" \
        bash -c "zcat \"$R1\" \"$R2\" > \"$MERGED\""
done

# === Parallelized HUMAnN3 functional profiling ===
export HUMANN_OUT


# Decide parallelization parameters
# Adjust -j (samples at once) and --threads per sample
PARALLEL_SAMPLES=2
THREADS_PER_SAMPLE=$((THREADS / PARALLEL_SAMPLES))

export HUMANN_OUT THREADS_PER_SAMPLE  # make vars visible to parallel

ls "$MERGED_READS_DIR"/*_merged.fastq | parallel -j $PARALLEL_SAMPLES "
    SAMPLE_ID=\$(basename {} \"_merged.fastq\")
    SAMPLE_LOG=\"\$HUMANN_OUT/\${SAMPLE_ID}.log\"
    GENE_OUTPUT=\"\$HUMANN_OUT/\${SAMPLE_ID}_merged_genefamilies.tsv\"

    if [ ! -f \"\$GENE_OUTPUT\" ]; then
        echo \"[INFO] Running HUMAnN3 on \$SAMPLE_ID\"
        humann --input {} --output \"\$HUMANN_OUT\" --threads \$THREADS_PER_SAMPLE > \"\$SAMPLE_LOG\" 2>&1
    else
        echo \"[INFO] Skipping HUMAnN3 for \$SAMPLE_ID (output exists)\"
    fi
"

# === Post-processing ===
GENEFAMILIES_CPM="$HUMANN_OUT/genefamilies_cpm.tsv"
POST_OUTPUTS="$GENEFAMILIES_CPM $HUMANN_OUT/genefamilies.tsv $HUMANN_OUT/pathabundance.tsv $HUMANN_OUT/pathabundance_relab.tsv"

run_step "HUMAnN post-processing" "$POST_OUTPUTS" bash -c "
humann_join_tables --input $HUMANN_OUT --output $HUMANN_OUT/genefamilies.tsv --file_name genefamilies
humann_join_tables --input $HUMANN_OUT --output $HUMANN_OUT/pathabundance.tsv --file_name pathabundance
humann_renorm_table --input $HUMANN_OUT/genefamilies.tsv --output $GENEFAMILIES_CPM --units cpm
humann_renorm_table --input $HUMANN_OUT/pathabundance.tsv --output $HUMANN_OUT/pathabundance_relab.tsv --units relab
"

echo "[INFO] HUMAnN3 pipeline finished successfully at $(date)" | tee -a "$LOGFILE"
