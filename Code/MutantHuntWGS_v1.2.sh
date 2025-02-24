#!/bin/bash
#SBATCH --cpus-per-task 36
#SBATCH --mem-per-cpu 4G
#SBATCH --time 1-00:00
#SBATCH --mail-type END,FAIL

#MutantHunter script by Mitch Ellison
#  edits by Christopher Bottoms, OMRF

# Assumes bowtie2, samtools, bcftools, and vcftools are available via $PATH

# Get script directory so that we know where dependent scripts are
script_dir=$( dirname $0 )
top_dir=$( dirname script_dir )

#Enable user input

while getopts n:g:f:r:s:p:d:o:a:t: option
do
case "${option}"
in
n) WILD_TYPE=${OPTARG};;
g) GENOME=${OPTARG};;
f) GENOME_FASTA=${OPTARG};;
r) READ_TYPE=${OPTARG};;
s) SCORE=${OPTARG};;
p) PLOIDY_FILE=${OPTARG};;
d) FASTQ_DIRECTORY=${OPTARG};;
o) OUTPUT_FILE=${OPTARG};;
a) ALIGNMENT_AND_CALLING=${OPTARG};;
t) CPUS=${OPTARG};;
esac
done


if [ -z "$WILD_TYPE" ]
then
      echo -e "-n option is empty"
      exit
fi

if [ -z "$GENOME" ]
then
      echo -e "-g option is empty"
      exit
fi

if [ -z "$GENOME_FASTA" ]
then
      echo -e "-f option is empty"
      exit
fi

if [ -z "$READ_TYPE" ]
then
      echo -e "-r option is empty"
      exit
fi

if [ -z "$SCORE" ]
then
      echo -e "-s option is empty"
      exit
fi

if [ -z "$PLOIDY_FILE" ]
then
      echo -e "-p option is empty"
      exit
fi

if [ -z "$FASTQ_DIRECTORY" ]
then
      echo -e "-d option is empty"
      exit
fi

if [ -z "$OUTPUT_FILE" ]
then
      echo -e "-o option is empty"
      exit
else
    OUTPUT_FILE=`realpath $OUTPUT_FILE`
fi

if [ -z "$ALIGNMENT_AND_CALLING" ]
then
      echo -e "-a option is empty"
      exit
fi

if [ -z "$CPUS" ]
then
      echo -e "-t option is empty"
      exit
fi

if [ "$ALIGNMENT_AND_CALLING" = "YES" ]
then
	#Remove Old Output directory
	rm -rf "$OUTPUT_FILE"

	#Make Output directory
	mkdir "$OUTPUT_FILE"

	#make some directories
	mkdir "$OUTPUT_FILE"/BAM
	mkdir "$OUTPUT_FILE"/Alignment_Stats
	mkdir "$OUTPUT_FILE"/BCF
	mkdir "$OUTPUT_FILE"/VCF
	mkdir "$OUTPUT_FILE"/VCFtools_Output
	mkdir "$OUTPUT_FILE"/SNPeff_Output
	mkdir "$OUTPUT_FILE"/SIFT_Output
    bam_out_dir="$OUTPUT_FILE/BAM"
    bcf_out_dir="$OUTPUT_FILE"/BCF
fi






if [ "$ALIGNMENT_AND_CALLING" = "YES" ]
then

	echo -e "\n\n\n\n\n\n"Running MutantHuntWGS

	###################################
	###     MODULE 1: Alignment     ###
	###################################

	echo -e "\n\n\n\n\n\n"Aligning Reads to the Genome "\n"

	#Align all datasets in a single module up-front as Jen Walker suggested

	#Apply the -r option to signify if the input is paired-end or single-end end reads

	if [ "$READ_TYPE" = "paired" ]
	then

	#Alignment of all FASTQ Files if -r paired is set

	#Run Bowtie 2 and convert output to BAM with Samtools

	##Loop to process all files starts here
	##map FASTQ files using for-loop


		for FASTQ_FILE in `ls "$FASTQ_DIRECTORY"/*_R1.fastq.gz`
		do

			##Align reads

			#Using this command to get only the file name and lose the path

			NAME_PREFIX=`echo "$FASTQ_FILE" | awk -F "/" '{print $(NF)}' | awk -F "_" '{print  $1}'`

            echo "Aligning $NAME_PREFIX"
			bowtie2 --no-unal \
				-q \
				-k 1 \
				-p "$CPUS" \
				-x "$GENOME" \
				-1 "$FASTQ_DIRECTORY"/"$NAME_PREFIX"_R1.fastq.gz -2 "$FASTQ_DIRECTORY"/"$NAME_PREFIX"_R2.fastq.gz \
				2> "$OUTPUT_FILE"/Alignment_Stats/"$NAME_PREFIX"_bowtie2.txt \
                | samtools view -b -q 30 \
                | samtools sort --threads $CPUS --write-index -o "$bam_out_dir/$NAME_PREFIX.bam##idx##$bam_out_dir/$NAME_PREFIX.bam.bai"

			echo  -e Reads from "$FASTQ_DIRECTORY"/"$NAME_PREFIX"*.fastq.gz Mapped "\n"and stored in $bam_out_dir/"$NAME_PREFIX".bam"\n"

		done


	elif [ "$READ_TYPE" = "single" ]
	then

        #TODO: Unify code, simply setting different FASTQ input line to be incorporated later

		for FASTQ_FILE in `ls "$FASTQ_DIRECTORY"/*.fastq.gz`
		do

			#Using this command to get only the file name and lose the path

			NAME_PREFIX=`echo "$FASTQ_FILE" | awk -F "/" '{print $(NF)}' | awk -F "." '{print  $1}'`

			##Align reads

			bowtie2 --no-unal \
				-q \
				-k 2 \
				-p "$CPUS" \
				-x "$GENOME" \
				-U "$FASTQ_DIRECTORY"/"$NAME_PREFIX".fastq.gz \
				2> "$OUTPUT_FILE"/Alignment_Stats/"$NAME_PREFIX"_bowtie2.txt \
				| samtools view -bS -q 30 > "$OUTPUT_FILE"/BAM/"$NAME_PREFIX".bam

			##Sort BAM with Samtools

			samtools sort "$OUTPUT_FILE"/BAM/"$NAME_PREFIX"_unsorted.bam -o "$OUTPUT_FILE"/BAM/"$NAME_PREFIX".bam

			##Index BAM with Samtools

			samtools index "$OUTPUT_FILE"/BAM/"$NAME_PREFIX".bam

			echo -e Reads from "$FASTQ_DIRECTORY"/"$NAME_PREFIX"*.fastq.gz mapped"\n"and stored in "$OUTPUT_FILE"/BAM/"$NAME_PREFIX".bam"\n"

		done

	else

		echo "Failed to Identify Read Type Files"
        exit

	fi


	###################################
	###  MODULE 2: Variant Calling  ###
	###################################

	echo -e "\n\n\n\n\n\n"Calling Variants "\n"

	for BAM_FILE in `ls "$OUTPUT_FILE"/BAM/*.bam`
	do

		#Using this command to get only the file name and lose the path
		NAME_PREFIX=`echo "$BAM_FILE" | awk -F "/" '{print $(NF)}' | sed 's/.bam$//' `

		#The first step is to use the SAMtools mpileup command to calculate the genotype likelihoods supported by the aligned reads in our sample

        echo "Running pileup on $NAME_PREFIX"
		bcftools mpileup \
            --threads 32 \
            --output-type b \
            --fasta-ref "$GENOME_FASTA" \
            --output $bcf_out_dir/"$NAME_PREFIX"_variants.bcf \
            "$BAM_FILE" \
            &> $bcf_out_dir/"$NAME_PREFIX"_mpileup.log # Capture standard error in a log

		#--output-type b : directs SAMtools to output genotype likelihoods in the binary call format (BCF). This is a compressed binary format.
		#A reference genome in FASTA format must be specified.

		#The second step is to use bcftools:
		#The bcftools call command uses the genotype likelihoods generated from the previous step to call SNPs and indels, and outputs the all identified variants in the variant call format (VFC), the file format created for the 1000 Genomes Project, and now widely used to represent genomic variants.

		echo "$BAM_FILE" | awk '{print $1 "\t" "M"}' > $bcf_out_dir/sample_file.txt

        echo "Running bcftools on $NAME_PREFIX"
		bcftools call \
            --threads 32 \
            -c \
            -v \
            --samples-file $bcf_out_dir/sample_file.txt \
            --ploidy-file "$PLOIDY_FILE" \
            $bcf_out_dir/"$NAME_PREFIX"_variants.bcf \
            > "$OUTPUT_FILE"/VCF/"$NAME_PREFIX"_variants.vcf

        ## Exclude variants with less than 30 depth, or where strand evidence is unbalanced
        #bcftools filter \
        #    --exclude 'INFO/DP < 30' \
        #    --exclude '(DP4[0]+DP4[2])/(DP4[1]+DP4[3]+1) < 0.5' \
        #    --exclude '(DP4[0]+DP4[2])/(DP4[1]+DP4[3]+1) > 2.0' \
        #    "$OUTPUT_FILE"/VCF/"$NAME_PREFIX"_variants.vcf > "$OUTPUT_FILE"/VCF/"$NAME_PREFIX"_variants.filtered_dp30.vcf

		#-c, --consensus-caller
		#-v, --variants-only


		echo -e Variants have been called and stored in "\n""$OUTPUT_FILE"/VCF/"$NAME_PREFIX"_variants.vcf"\n"

	done

fi


if [ "$ALIGNMENT_AND_CALLING" = "NO" ]
then

	mkdir "$OUTPUT_FILE"/VCFtools_Output

fi



if [ `ls "$OUTPUT_FILE"/BAM | wc -l` -gt 0 ]
then

	#############################################
	###  MODULE 3: Filter and Score Variants  ###
	#############################################

	echo -e "\n\n\n\n\n\n"Comparing all strains to the "$WILD_TYPE" wild-type strain "\n"


	##############################
	#Implementing Payals Fix Here

	#Merge all vcf files with the mock_variant.tmp file
	cat "$OUTPUT_FILE"/VCF/"$WILD_TYPE"_variants.vcf /hpc-prj/cbds/software/MutantHuntWGS/S_cerevisiae_Bowtie2_Index_and_FASTA/mock_variant.tsv > "$OUTPUT_FILE"/VCF/"$WILD_TYPE"_variants_merged.vcf

	#Create sorted vcf by catenating header in file and sort the non-header and append to the existing file
	for d in "$OUTPUT_FILE"/VCF/"$WILD_TYPE"_variants_merged.vcf; do grep "^#" $d > $d.sorted; grep -v "^#" $d | sort -k1,1V -k2,2g >> $d.sorted; done

	#END Payals fix code
	##############################


	#WILD_TYPE = the wild type file to compare all other files too

	for MUTANT_VCF in `ls "$OUTPUT_FILE"/VCF/*_variants.vcf`
	do

		#Using this command to get only the file name and lose the path
		MUTANT=`echo "$MUTANT_VCF" | awk -F "/" '{print $(NF)}' | sed 's/.vcf$//'`


		##############################
		#Implementing Payals Fix Here

		#Merge all vcf files with the mock_variant.tmp file
		cat "$OUTPUT_FILE"/VCF/"$MUTANT".vcf /hpc-prj/cbds/software/MutantHuntWGS/S_cerevisiae_Bowtie2_Index_and_FASTA/mock_variant.tsv > "$OUTPUT_FILE"/VCF/"$MUTANT"_merged.vcf

		#Create sorted vcf by catenating header in file and sort the non-header and append to the existing file
		for d in "$OUTPUT_FILE"/VCF/"$MUTANT"_merged.vcf; do grep "^#" $d > $d.sorted; grep -v "^#" $d | sort -k1,1V -k2,2g >> $d.sorted; done

		#END Payals fix code
		##############################



		#Compare variations in the two files

		vcftools --vcf "$OUTPUT_FILE"/VCF/"$MUTANT"_merged.vcf.sorted --diff "$OUTPUT_FILE"/VCF/"$WILD_TYPE"_variants_merged.vcf.sorted --diff-site --out "$OUTPUT_FILE"/VCFtools_Output/"$MUTANT"_vs_"$WILD_TYPE"_VCFtools_output.txt

		##These next two steps are to produce VCF files from the output for downstream applications

		##Here I am using awk to remove the third column so that I can make files for use with the grep command below

		awk -F "\t" '$2 != $3' "$OUTPUT_FILE"/VCFtools_Output/"$MUTANT"_vs_"$WILD_TYPE"_VCFtools_output.txt.diff.sites_in_files | awk -F "\t" '$3 == "." {print $1 "\t" $2}' > "$OUTPUT_FILE"/VCFtools_Output/"$MUTANT"_vs_"$WILD_TYPE"_for_grep.txt


		#VCF file construction

		##Grep variants of intrest from Mutant VCF

		grep -f "$OUTPUT_FILE"/VCFtools_Output/"$MUTANT"_vs_"$WILD_TYPE"_for_grep.txt "$OUTPUT_FILE"/VCF/"$MUTANT".vcf > "$OUTPUT_FILE"/VCF/"$MUTANT"_filtered.tmp


		#Get VCF header information so we can add it to the new file allowing it to be viewed in IGV
		grep "^#" "$OUTPUT_FILE"/VCF/"$MUTANT".vcf > "$OUTPUT_FILE"/VCF/VCF_header.tmp

		#Score variants based on user input
		awk ' $6 >= '$SCORE' {print}' "$OUTPUT_FILE"/VCF/"$MUTANT"_filtered.tmp > "$OUTPUT_FILE"/VCF/"$MUTANT"_filtered_and_scored.tmp

		#Add header to filtered variants to generate a proper VCF file
		cat "$OUTPUT_FILE"/VCF/VCF_header.tmp "$OUTPUT_FILE"/VCF/"$MUTANT"_filtered.tmp > "$OUTPUT_FILE"/VCF/"$MUTANT"_filtered.vcf

		#Add header to filtered and scored variants to generate a proper VCF file
		cat "$OUTPUT_FILE"/VCF/VCF_header.tmp "$OUTPUT_FILE"/VCF/"$MUTANT"_filtered_and_scored.tmp > "$OUTPUT_FILE"/VCF/"$MUTANT"_filtered_and_scored.vcf


	done

	echo -e Comparisons complete


	#Remove unwanted directories
	#rm -rf "$OUTPUT_FILE"/BCF
	#rm -rf "$OUTPUT_FILE"/VCFtools_Output

	#Remove unwanted files
	#rm "$OUTPUT_FILE"/BAM/*_unsorted.bam
	#rm "$OUTPUT_FILE"/VCF/*.tmp
	#rm `ls "$OUTPUT_FILE"/VCF/"$WILD_TYPE"_variants_filtered*.vcf`
	#rm "$OUTPUT_FILE"/VCF/*_merged.vcf
	#rm "$OUTPUT_FILE"/VCF/*_merged.vcf.sorted



	###########################################################
	###   MODULE 4: Determine Variant Effects with SNPeff   ###
	###########################################################

	echo -e "\n\n\n\n\n\n"Running SNPeff  "\n"


	cd "$OUTPUT_FILE"/SNPeff_Output

	for VCF_FILE in `ls "$OUTPUT_FILE"/VCF/*_filtered_and_scored.vcf`
	do

		#Using this command to get only the file name and lose the path
		VCF_NAME=`echo "$VCF_FILE" | awk -F "/" '{print $(NF)}' | awk -F "_" '{print  $1}'`


		# Determine if VCF file contains variants
		if [ `grep -v "^#" "$VCF_FILE" | wc -l` = 0 ]
		then

			# Print Error Message
			echo -e ERROR: Unable to Run SNPeff because there are no variants in: "\n" "$VCF_NAME"

		else

			#Make directory
			mkdir "$OUTPUT_FILE"/SNPeff_Output/"$VCF_NAME"

			#set as working directory
			cd "$OUTPUT_FILE"/SNPeff_Output/"$VCF_NAME"

			#Use SNPeff to find out some more information about these SNPs like the amino acid change in the resulting protein

			snpEff ann -v Saccharomyces_cerevisiae "$VCF_FILE" > "$OUTPUT_FILE"/SNPeff_Output/"$VCF_NAME"/SNPeff_Annotations.vcf

		fi

	done



	#################################################################
	###   MODULE 5: Predict Variant Impact on Protein with SIFT   ###
	#################################################################

	echo -e "\n\n\n\n\n\n"Running SIFT  "\n"

	for VCF_FILE in `ls "$OUTPUT_FILE"/VCF/*_filtered_and_scored.vcf`
	do

		#Using this command to get only the file name and lose the path
		VCF_NAME=`echo "$VCF_FILE" | awk -F "/" '{print $(NF)}' | awk -F "_" '{print  $1}'`

		# Determine if VCF file contains variants
		if [ `grep -v "^#" "$VCF_FILE" | wc -l` = 0 ]
		then

			echo -e ERROR: Unable to Run SIFT because there are no variants in: "\n" "$VCF_NAME"

		else

			##Run SIFT
			java -Xmx4G -jar $script_dir/SIFT4G_Annotator.jar -c -i "$VCF_FILE"  -d /Main/EF4.74 -r "$OUTPUT_FILE"/SIFT_Output/"$VCF_NAME"


		fi

	done

	echo -e "\n\n\n\n\n\n" Run Completed "\n\n\n\n"

	exit

else
	exit
fi
