#!/bin/bash

# Enable verbose output for debugging
set -x

# Initialize variables for input parameters
T1_FILE=""
TEMPLATE_FILE=""
PROBABILITY_MASK=""
REGISTRATION_MASK=""
ATLAS_FILE=""
REFERENCE_FILE=""
OUTPUT_DIR=""

# Parse the input flags
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --t1) T1_FILE="$2"; shift ;;
        --template) TEMPLATE_FILE="$2"; shift ;;
        --probability-mask) PROBABILITY_MASK="$2"; shift ;;
        --registration-mask) REGISTRATION_MASK="$2"; shift ;;
        --atlas) ATLAS_FILE="$2"; shift ;;
        --reference) REFERENCE_FILE="$2"; shift ;;
        --output) OUTPUT_DIR="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Check if all required input parameters are provided
if [ -z "$T1_FILE" ] || [ -z "$TEMPLATE_FILE" ] || [ -z "$PROBABILITY_MASK" ] || [ -z "$REGISTRATION_MASK" ] || [ -z "$ATLAS_FILE" ] || [ -z "$REFERENCE_FILE" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 --t1 <T1_FILE> --template <TEMPLATE_FILE> --probability-mask <PROBABILITY_MASK> --registration-mask <REGISTRATION_MASK> --atlas <ATLAS_FILE> --reference <REFERENCE_FILE> --output <OUTPUT_DIR>"
    exit 1
fi

# Verify that all files and directories exist
for file in "$T1_FILE" "$TEMPLATE_FILE" "$PROBABILITY_MASK" "$REGISTRATION_MASK" "$ATLAS_FILE" "$REFERENCE_FILE"; do
    if [ ! -e "$file" ]; then
        echo "Error: File or directory does not exist: $file"
        exit 1
    fi
done

# Verify that the output directory exists or create it if necessary
if [ ! -d "$OUTPUT_DIR" ]; then
    echo "Creating output directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
fi

# Create subdirectories within the output directory
echo "Creating output subdirectories..."
mkdir -p "$OUTPUT_DIR/N4SS" "$OUTPUT_DIR/REG" "$OUTPUT_DIR/WARP"

# Step 1: Brain extraction
echo "Starting brain extraction..."
antsBrainExtraction.sh \
    -d 3 \
    -a "$T1_FILE" \
    -e "$TEMPLATE_FILE" \
    -m "$PROBABILITY_MASK" \
    -o "$OUTPUT_DIR/N4SS/N4SS" \
    -f "$REGISTRATION_MASK"

echo "Brain extraction completed."

# Step 2: Registration of the T1-weighted image to the reference brain
echo "Starting registration..."
antsRegistration \
    --dimensionality 3 \
    --float 0 \
    --output ["$OUTPUT_DIR/REG/reg_","$OUTPUT_DIR/REG/reg_Warped.nii.gz"] \
    --interpolation Linear \
    --winsorize-image-intensities [0.005,0.995] \
    --use-histogram-matching 0 \
    --initial-moving-transform ["$REFERENCE_FILE","$OUTPUT_DIR/N4SS/N4SSBrainExtractionBrain.nii.gz",1] \
    --transform Affine[0.1] \
    --metric MI["$REFERENCE_FILE","$OUTPUT_DIR/N4SS/N4SSBrainExtractionBrain.nii.gz",1,32,Regular,0.25] \
    --convergence [1000x500x250x100,1e-6,10] \
    --shrink-factors 8x4x2x1 \
    --smoothing-sigmas 3x2x1x0vox \
    --transform SyN[0.1,3,0] \
    --metric CC["$REFERENCE_FILE","$OUTPUT_DIR/N4SS/N4SSBrainExtractionBrain.nii.gz",1,4] \
    --convergence [200x140x100x40,1e-6,10] \
    --shrink-factors 8x4x2x1 \
    --smoothing-sigmas 3x2x1x0vox \
    -v

echo "Registration completed."

# Step 3: Warp the atlas labels to the subject's native space
echo "Starting atlas label warping..."
antsApplyTransforms \
    -d 3 \
    -i "$ATLAS_FILE" \
    -r "$OUTPUT_DIR/N4SS/N4SSBrainExtractionBrain.nii.gz" \
    -o "$OUTPUT_DIR/WARP/result.nii.gz" \
    -t "$OUTPUT_DIR/REG/reg_1InverseWarp.nii.gz" \
    -t ["$OUTPUT_DIR/REG/reg_0GenericAffine.mat", 1] \
    -n NearestNeighbor

echo "Atlas label warping completed."
