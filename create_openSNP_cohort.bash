#!/bin/bash -
#===============================================================================
#
#          FILE: create_openSNP_cohort.bash
#
#         USAGE: ./create_openSNP_cohort.bash
#
#   DESCRIPTION: see README.md 
#
#       OPTIONS: Adjust the number of cores available by changing variable 'nb_proc'
#  REQUIREMENTS: Install all dependencies as explained in the README.md file
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: OLIVIER NARET (ON), onaret@gmail.com
#  ORGANIZATION: EPFL
#       CREATED: 01/01/2017 03:14:36 PM
#      REVISION:  ---
#===============================================================================

nb_proc=4

#requirement, libpng-dev
#For liftover...
#wget -q -O /tmp/libpng12.deb http://mirrors.kernel.org/ubuntu/pool/main/libp/libpng/libpng12-0_1.2.54-1ubuntu1_amd64.deb \
#    && dpkg -i /tmp/libpng12.deb \
#      && rm /tmp/libpng12.deb

hg19="ref/human_g1k_v37.fasta"
rename=$(readlink -f bin/rename)
gunzip=$(readlink -f bin/gunzip)
unzip=$(readlink -f bin/unzip)
plink=$(readlink -f bin/plink)
liftmap=$(readlink -f bin/LiftMap.py) 
vcf_sort=$(readlink -f bin/vcf-sort)
bgzip=$(readlink -f bin/bgzip)
bcftools=$(readlink -f bin/bcftools)
hg19=$(readlink -f $hg19)

mkdir -p openSNP{/discarded/{size-excluded,exome,others,decodeme,dup},/log}

echo $(date): Downloading...
if [ ! -f opensnp_datadump.current.zip ]; then
  wget https://opensnp.org/data/zip/opensnp_datadump.current.zip
fi
exit
echo $(date): Unzipping... log in log/unzipping.log
$unzip opensnp_datadump.current.zip -d openSNP &> openSNP/log/unzipping.log
cd openSNP

echo $(date): Renaming files...
$rename 's/user//g;s/_file/./g;s/_yearofbirth_.*?\./\./g' *

echo $(date): Excluding file under 10M and over 50M...
find . -maxdepth 1 -type f -size -10M -exec mv {} discarded/size-excluded \;
find . -maxdepth 1 -type f -size +50M -exec mv {} discarded/size-excluded \;

echo $(date): Sorting files...
function sort_it {
	mkdir -p discarded/$filetype
	mv $filename discarded/$filetype/
}

while read -r line; do
  filename=$(awk -F':' '{print $1}' <<< $line)
  filetype=$(awk '{print $2}' <<< $line)
  if [[ $filetype == "gzip" ]]; then
		$rename 's/$/.gz/' $filename
		$gunzip "$filename.gz" > /dev/null
    filetype=$(file $filename | awk '{print $2}')
    sort_it
	
	elif [[ $filetype == "Zip" ]]; then
    $unzip -l $filename | grep -Fq '1 file'
    if [[ $? == 0 ]]; then
      mkdir $filename.d
		  $unzip $filename -d $filename.d > /dev/null
		  rm $filename 
		  mv $filename.d/* $filename
      rmdir $filename.d
      filetype=$(file $filename | awk '{print $2}')
			sort_it
		else
			mkdir -p discarded/multiple_files_zip
			mv $filename discarded/multiple_files_zip/
		fi
	else
		sort_it
	fi
done < <(find . -maxdepth 1 -type f -exec file {} \;)

mv discarded{/ASCII/*,/RSID/*} .
rmdir discarded/{ASCII,RSID}

#Remove exome and decodme files
mv *exome* discarded/exome
mv *decodeme* discarded/decodeme

#Deal with people that uploaded their genome multiple times
echo $(date): Keep only the biggest file between, duplicated, multi imputed, and sample genotyped by different company...

#move all concerned samples a dup folder
find -maxdepth 1 -type f -printf "%f\n" | cut -f1 -d '.' | sort | uniq -d | sed 's/$/\.\*/g' | xargs -I {} bash -c "mv {} discarded/dup"

#This sample as both ancestry and 23andme and ancestry is both the biggest and the buggued one
rm discarded/dup/*3641*ancestry.txt

#compare files to extract the biggest
ls discarded/dup/ | cut -f1 -d '.' | sort | uniq -d | sed 's/$/\.\*/g' | xargs -I {} bash -c "wc -l discarded/dup/{} |  sort -nr | cut -f2 |  tr -s ' ' | sed 's/^ //g' | sort -nr | cut -f2 -d ' ' |  sed -n 2p" | xargs -I {} bash -c "mv {} ."

#remove file number
$rename 's/\.+?[0-9]+//' *

###Formatting
echo $(date): Formatting file coming from different companies...
#Formatter, set endline to unix, set norm to ensemble from plink or ucsc
find -maxdepth 1 -type f | xargs -P$nb_proc -I {} sed -i 's/\r$//;s/rsid/ d/gI;/^#/ d;s/ \+/\t/g;s/\"//g;s/,/\t/g;s/chr//g;s/\tXY\t/\tX\t/g;s/\tM\t/\tMT\t/g;s/\t25\t/\t23\t/g' {}

find *ancestry* -maxdepth 1 -type f | xargs -P$nb_proc -I {} bash -c "awk '{print \$1,\$2,\$3,\$4\$5}' {} | sed 's/ /\t/g' > {}.tmp"
rm *ancestry*.txt
$rename 's/\.tmp//g' *

#Need to be sorted here for future conversions
echo $(date): Sorting...
find -maxdepth 1 -type f | xargs -P$nb_proc -I {} sh -c 'for i in $(seq 1 26) X XY Y MT M; do awk -F"\t" -vi="$i" "{if ( i==\$2 ) {print $1}}" {}; done > {}.tmp'
rm *.txt
$rename 's/\.tmp//g' *

echo $(date): Formating outliers...
###Build36
#Incomplete
mv 158.23andme.txt discarded/others
#Unknown error after lifting when converting back to VCF
mv 6.23andme.txt discarded/others
sed -i 's/\-\-\-/--/g' 981.ftdna-illumina.txt

###build37
#Weird, could be fixed but rather discard it
mv 1059.23andme.txt discarded/others

sed -i -e '625087d' 2210.ancestry.txt
sed -i -f <(cut -f3 1168.ftdna-illumina.txt | uniq -d |  sed "s/^/\/\\t/g;s/$/\\t\/d/g") 1168.ftdna-illumina.txt
sed -i '/^SNP/ d;/^AFFX-SNP_6488364__NA/ d' 77.23andme.txt
sed -i -e '700577,700593d' 1964.23andme.txt
sed -i -e '9468d' 4192.23andme.txt

echo $(date): Determining build reference
mkdir -p build36/{pedmap,lifted} build{37,38} fixed vcf merged log sorted renamed
find -maxdepth 1 -type f | xargs -P$nb_proc -I {} grep -HP 'rs28415373\t1\t883844' {} | awk -F':' '{print $1}' | xargs -I {} mv {} build36/
find -maxdepth 1 -type f | xargs -P$nb_proc -I {} grep -HP 'rs28415373\t1\t893981' {} | awk -F':' '{print $1}'| xargs -I {} mv {} build37/
find -maxdepth 1 -type f | xargs -P$nb_proc -I {} grep -HP 'rs3094315\t1\t742429' {} | awk -F':' '{print $1}' | xargs -I {} mv {} build36/
find -maxdepth 1 -type f | xargs -P$nb_proc -I {} grep -HP 'rs3094315\t1\t752566' {} | awk -F':' '{print $1}'| xargs -I {} mv {} build37/
find -maxdepth 1 -type f | xargs -P$nb_proc -I {} grep -HP 'rs12564807\t1\t734462' {} | awk -F':' '{print $1}'| xargs -I {} mv {} build37/
find -maxdepth 1 -type f | xargs -P$nb_proc -I {} grep -HP 'rs11240777\t1\t798959' {} | awk -F':' '{print $1}'| xargs -I {} mv {} build37/
find -maxdepth 1 -type f | xargs -P$nb_proc -I {} grep -HP 'rs7537756\t1\t854250' {} | awk -F':' '{print $1}'| xargs -I {} mv {} build37/
find -maxdepth 1 -type f | xargs -P$nb_proc -I {} grep -HP 'rs145997327\t1\t10889805*' {} | awk -F':' '{print $1}'| xargs -I {} mv {} build38/
find -maxdepth 1 -type f | xargs -P$nb_proc -I {} grep -HP 'rs2308040\t1\t13779899' {} | awk -F':' '{print $1}'| xargs -I {} mv {} build38/

####Lift build36
echo $(date): Lift and convert samples from build 36 to 37... log in log/\{b36_convert_to_vcf.log, b36_lifting.log, b36_convert_to_vcf.log\}

#convert directly from 23 to ped/map for lifting
find build36/*.txt -maxdepth 1 -type f -printf "%f\n" | xargs -P$nb_proc -I {} $plink --23file build36/{} --output-chr 'MT' --recode --out build36/pedmap/{} &> log/b36_convert_to_plink.log

#lift
find build36/*.txt -maxdepth 1 -type f -printf "%f\n" | xargs -P$nb_proc -I {} $liftmap -m build36/pedmap/{}.map -p build36/pedmap/{}.ped -o build36/lifted/{} &> log/b36_lifting.log

#convert back to vcf
find build36/*.txt -maxdepth 1 -type f -printf "%f\n" | xargs -P$nb_proc -I {} $plink --file build36/lifted/{} --recode vcf-iid --output-chr 'MT' --snps-only just-acgt --biallelic-only strict --keep-allele-order --out vcf/{} &> log/b36_convert_to_vcf.log

####Convert build37
echo $(date): convert build 37 to vcf... log in log/b37_convert_to_vcf.log
find build37/* -printf "%f\n" | xargs -P$nb_proc -I {} $plink --23file build37/{} --recode vcf-iid --output-chr 'MT' --snps-only just-acgt --biallelic-only strict --keep-allele-order --out vcf/{} &> log/b37_convert_to_vcf.log

echo $(date): Fix annotation... log in log/fixed.log
find vcf/*.vcf -printf "%f\n" | xargs -P$nb_proc -I {} $bcftools norm -f $hg19 -c s vcf/{} -o fixed/{} &> log/fixed.log

#Need to be sorted again after fixing samples to the same reference
echo $(date): Sorting... log in log/sorted.log
find fixed/* -printf "%f\n" | xargs -P$nb_proc -I {} sh -c "$vcf_sort -c fixed/{} > sorted/{}" &> log/sorted.log

echo $(date): Renaming samples...
find sorted/* -printf "%f\n" | xargs -P$nb_proc -I {} bash -c "$bcftools reheader sorted/{}  -s <(cut -d '.' -f1 <<<'{}') -o renamed/{}"

echo $(date): Bgziping...
find renamed/* | xargs -P$nb_proc -I {} $bgzip {}

echo $(date): Indexing...
find renamed/* | xargs -P$nb_proc -I {} $bcftools index {}

echo $(date): Merging...
nb_files=$(ls renamed/*.gz | wc -l)
for i in $(seq 1 $((nb_files/100))); do $bcftools merge -l <(ls renamed/*.gz | head -n $((i*100)) | tail -n 100) --threads $nb_proc -Oz -o merged/part.${i}.gz; done
$bcftools merge -l <(ls renamed/*.gz | tail -n $((nb_files%100))) --threads $nb_proc -Oz -o merged/part.rest.gz
find merged/*.gz | xargs -P$nb_proc -I {} $bcftools index {} 
$bcftools merge -l <(ls merged/part*gz) --threads $nb_proc -Oz -o merged/openSNP_dataset.vcf.gz
$bcftools index merged/openSNP_dataset.vcf.gz

$plink --vcf merged/openSNP_dataset.vcf.gz --geno 0.9 --hwe 1e-50 --recode vcf-iid bgz --keep-allele-order  --output-chr 'MT' --remove-fam <($bcftools +guess-ploidy -g b37 openSNP_dataset.vcf.gz | grep U | grep -P '[0-9]*' -o) --out openSNP_dataset_QC

echo $(date): Done! You can know impute the file openSNP_dataset_QC.vcf.gz on Sanger Imputation Service https://imputation.sanger.ac.uk/

