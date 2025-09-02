#!/bin/bash
set -euo pipefail

LOGFILE="humann_runtime.log"
RESUME=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --resume) RESUME=true ;;
    esac
done

echo "=== HUMAnN3 run started at $(date) ===" >> "$LOGFILE"

run_step() {
    step_name=$1
    shift
    output_files=$1
    shift

    # If RESUME is enabled and all output files exist, skip
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

# === Load config and conda ===
source ~/gut/h3_config.env

# === Create database directories ===
mkdir -p "$HUMANN_CHOCO_DB" "$HUMANN_UNIREF_DB" "$HUMANN_DB_DIR"

# === HUMAnN database setup ===
run_step "HUMAnN database setup" "$HUMANN_CHOCO_DB $HUMANN_UNIREF_DB" bash -c "
# ChocoPhlAn
if [ -z \"\$(ls -A \"$HUMANN_CHOCO_DB\")\" ]; then
    echo \"[INFO] Downloading latest ChocoPhlAn database...\"
    humann_databases --download chocophlan full \"$HUMANN_CHOCO_DB\"
else
    echo \"[INFO] ChocoPhlAn database already exists, skipping download.\"
fi

# UniRef
if [ -z \"\$(ls -A \"$HUMANN_UNIREF_DB\")\" ]; then
    echo \"[INFO] Downloading UniRef database ($HUMANN_UNIREF_TYPE)...\"
    humann_databases --download uniref \"$HUMANN_UNIREF_TYPE\" \"$HUMANN_UNIREF_DB\"
else
    echo \"[INFO] UniRef database already exists, skipping download.\"
fi

# Update HUMAnN config
humann_config --update database_folders nucleotide \"$HUMANN_CHOCO_DB\"
humann_config --update database_folders protein \"$HUMANN_UNIREF_DB\"
"

# === Merge KneadData paired reads dynamically ===
mkdir -p "$HUMANN_OUT/merged_reads"
MERGED_READS_DIR="$HUMANN_OUT/merged_reads"

for R1 in p3_349_st/output/kneaddata_cleaned/*_paired_1.fastq; do
    SAMPLE_ID=$(basename "$R1" "_paired_1.fastq")
    R2="${R1/_paired_1.fastq/_paired_2.fastq}"
    MERGED="$MERGED_READS_DIR/${SAMPLE_ID}_merged.fastq"

    run_step "Merge $SAMPLE_ID paired reads" "$MERGED" \
        bash -c "cat \"$R1\" \"$R2\" > \"$MERGED\""
done

# === Functional profiling per merged sample ===
mkdir -p "$HUMANN_OUT"

for MERGED in "$MERGED_READS_DIR"/*_merged.fastq; do
    SAMPLE_ID=$(basename "$MERGED" "_merged.fastq")
    GENE_OUTPUT="$HUMANN_OUT/${SAMPLE_ID}_genefamilies.tsv"

    if [ "$USE_BRACKEN" = "true" ]; then
        BRACKEN_HUMANN="$HUMANN_OUT/${SAMPLE_ID}.bracken.humann.tsv"

        run_step "Convert Bracken to HUMAnN profile" "$BRACKEN_HUMANN" \
            python3 ~/p3_349_st/output/brackentohumann.py "./p3_349_st/output/p3_349_st.bracken.species" "$BRACKEN_HUMANN"

        run_step "HUMAnN3 with Bracken taxonomy" "$GENE_OUTPUT" humann \
            --input "$MERGED" \
            --output "$HUMANN_OUT" \
            #--taxonomic-profile $BRACKEN_HUMANN \
            --threads "$THREADS"
    else
        run_step "HUMAnN3 with MetaPhlAn taxonomy" "$GENE_OUTPUT" humann \
            --input "$MERGED" \
            --output "$HUMANN_OUT" \
            --threads "$THREADS"
    fi
done

# === Post-processing ===
GENEFAMILIES_CPM="$HUMANN_OUT/genefamilies_cpm.tsv"
POST_OUTPUTS="$GENEFAMILIES_CPM $HUMANN_OUT/genefamilies.tsv $HUMANN_OUT/pathabundance.tsv $HUMANN_OUT/pathabundance_relab.tsv"

run_step "HUMAnN post-processing" "$POST_OUTPUTS" bash -c "
humann_join_tables --input $HUMANN_OUT --output $HUMANN_OUT/genefamilies.tsv --file_name genefamilies
humann_join_tables --input $HUMANN_OUT --output $HUMANN_OUT/pathabundance.tsv --file_name pathabundance
humann_normalize_table --input $HUMANN_OUT/genefamilies.tsv --output $GENEFAMILIES_CPM --units cpm
humann_normalize_table --input $HUMANN_OUT/pathabundance.tsv --output $HUMANN_OUT/pathabundance_relab.tsv --units relab
"

echo "[INFO] HUMAnN3 pipeline finished successfully at $(date)" | tee -a "$LOGFILE"

