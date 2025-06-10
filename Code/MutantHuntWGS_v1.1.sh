#!/bin/bash

#MutantHunter script by Mitch Ellison
#Edits by Hoa Chuongh and Christopher Bottoms


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

			bowtie2 --no-unal \
				-q \
				-k 2 \
				-p "$CPUS" \
				-x "$GENOME" \
				-1 "$FASTQ_DIRECTORY"/"$NAME_PREFIX"_R1.fastq.gz -2 "$FASTQ_DIRECTORY"/"$NAME_PREFIX"_R2.fastq.gz \
				2> "$OUTPUT_FILE"/Alignment_Stats/"$NAME_PREFIX"_bowtie2.txt \
				| samtools view - -bS -q 30 > "$OUTPUT_FILE"/BAM/"$NAME_PREFIX"_unsorted.bam

			##Sort BAM with Samtools

			samtools sort --threads "$CPUS" "$OUTPUT_FILE"/BAM/"$NAME_PREFIX"_unsorted.bam -o "$OUTPUT_FILE"/BAM/"$NAME_PREFIX"_sorted.bam

			##Index BAM with Samtools

			samtools index --threads "$CPUS" "$OUTPUT_FILE"/BAM/"$NAME_PREFIX"_sorted.bam

			echo  -e Reads from "$FASTQ_DIRECTORY"/"$NAME_PREFIX"*.fastq.gz Mapped "\n"and stored in "$OUTPUT_FILE"/BAM/"$NAME_PREFIX"_sorted.bam"\n"

		done


	elif [ "$READ_TYPE" = "single" ]
	then


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
				| samtools view - -bS -q 30 > "$OUTPUT_FILE"/BAM/"$NAME_PREFIX"_unsorted.bam

			##Sort BAM with Samtools

			samtools sort --threads "$CPUS" "$OUTPUT_FILE"/BAM/"$NAME_PREFIX"_unsorted.bam -o "$OUTPUT_FILE"/BAM/"$NAME_PREFIX"_sorted.bam

			##Index BAM with Samtools

			samtools index --threads "$CPUS" "$OUTPUT_FILE"/BAM/"$NAME_PREFIX"_sorted.bam

			echo -e Reads from "$FASTQ_DIRECTORY"/"$NAME_PREFIX"*.fastq.gz mapped"\n"and stored in "$OUTPUT_FILE"/BAM/"$NAME_PREFIX"_sorted.bam"\n"

		done

	else

		echo "Failed to Identify Read Type Files"

	fi


	###################################
	###  MODULE 2: Variant Calling  ###
	###################################

	echo -e "\n\n\n\n\n\n"Calling Variants "\n"

	for BAM_FILE in `ls "$OUTPUT_FILE"/BAM/*_sorted.bam`
	do

		#Using this command to get only the file name and lose the path
		NAME_PREFIX=`echo "$BAM_FILE" | awk -F "/" '{print $(NF)}' | awk -F "_" '{print  $1}'`

		#The first step is to use the bcftools mpileup command to calculate the genotype likelihoods supported by the aligned reads in our sample
	

		bcftools mpileup -f "$GENOME_FASTA" "$BAM_FILE" -o "$OUTPUT_FILE"/BCF/"$NAME_PREFIX"_variants.bcf &> /dev/null

		#-f: directs bcftools to use the specified reference genome. A reference genome must be specified.

		#The second step is to use bcftools:
		#The bcftools call command uses the genotype likelihoods generated from the previous step to call SNPs and indels, and outputs the all identified variants in the variant call format (VFC), the file format created for the 1000 Genomes Project, and now widely used to represent genomic variants.

		echo "$BAM_FILE" | awk '{print $1 "\t" "M"}' > "$OUTPUT_FILE"/BCF/sample_file.txt

		bcftools call -c -v --samples-file "$OUTPUT_FILE"/BCF/sample_file.txt --ploidy-file "$PLOIDY_FILE" "$OUTPUT_FILE"/BCF/"$NAME_PREFIX"_variants.bcf > "$OUTPUT_FILE"/VCF/"$NAME_PREFIX"_variants.vcf

		#-c, --consensus-caller
		#-v, --variants-only


		echo -e Variants have been called and stored in "\n""$OUTPUT_FILE"/VCF/"$NAME_PREFIX"_variants.vcf"\n"

	done

fi


if [ "$ALIGNMENT_AND_CALLING" = "NO" ]
then

	mkdir "$OUTPUT_FILE"/VCFtools_Output

fi



if [ `ls "$OUTPUT_FILE"/BAM | wc -l` > 0 ]
then

	#############################################
	###  MODULE 3: Filter and Score Variants  ###
	#############################################

	echo -e "\n\n\n\n\n\n"Comparing all strains to the "$WILD_TYPE" wild-type strain "\n"


	##############################
	#Implementing Payals Fix Here

	#Merge all vcf files with the mock_variant.tmp file
	cat "$OUTPUT_FILE"/VCF/"$WILD_TYPE"_variants.vcf /Main/MutantHuntWGS/S_cerevisiae_Bowtie2_Index_and_FASTA/mock_variant.tsv > "$OUTPUT_FILE"/VCF/"$WILD_TYPE"_variants_merged.vcf

	#Create sorted vcf by catenating header in file and sort the non-header and append to the existing file
	for d in "$OUTPUT_FILE"/VCF/"$WILD_TYPE"_variants_merged.vcf; do grep "^#" $d > $d.sorted; grep -v "^#" $d | sort -k1,1V -k2,2g >> $d.sorted; done

	#END Payals fix code
	##############################


	#WILD_TYPE = the wild type file to compare all other files too

	for MUTANT_VCF in `ls "$OUTPUT_FILE"/VCF/*_variants.vcf`
	do

		#Using this command to get only the file name and lose the path
		MUTANT=`echo "$MUTANT_VCF" | awk -F "/" '{print $(NF)}' | awk -F "." '{print  $1}'`



		##############################
		#Implementing Payals Fix Here

		#Merge all vcf files with the mock_variant.tmp file
		cat "$OUTPUT_FILE"/VCF/"$MUTANT".vcf /Main/MutantHuntWGS/S_cerevisiae_Bowtie2_Index_and_FASTA/mock_variant.tsv > "$OUTPUT_FILE"/VCF/"$MUTANT"_merged.vcf

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
	rm -rf "$OUTPUT_FILE"/BCF
	rm -rf "$OUTPUT_FILE"/VCFtools_Output

	#Remove unwanted files
	rm "$OUTPUT_FILE"/BAM/*_unsorted.bam
	rm "$OUTPUT_FILE"/VCF/*.tmp
	rm `ls "$OUTPUT_FILE"/VCF/"$WILD_TYPE"_variants_filtered*.vcf`
	rm "$OUTPUT_FILE"/VCF/*_merged.vcf
	rm "$OUTPUT_FILE"/VCF/*_merged.vcf.sorted
	
	

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

			java -Xmx4G -jar /Main/snpEff/snpEff.jar ann -v Saccharomyces_cerevisiae "$VCF_FILE" > "$OUTPUT_FILE"/SNPeff_Output/"$VCF_NAME"/SNPeff_Annotations.vcf

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
			java -Xmx4G -jar /Main/SIFT4G_Annotator.jar -c -i "$VCF_FILE"  -d /Main/EF4.74 -r "$OUTPUT_FILE"/SIFT_Output/"$VCF_NAME"


		fi

	done

	echo -e "\n\n\n\n\n\n" Run Completed "\n\n\n\n"

	exit

else
	exit
fi
