#!/bin/bash

export LC_ALL=C

# Begin configuration section.
cmd=run.pl
# End configuration options.

echo "$0 $@"  # Print the command line for logging

[ -f path.sh ] && . ./path.sh # source the path.
. parse_options.sh || exit 1;

if [ $# != 2 ]; then
   echo "usage: common/train_joint_morfessor_segmentation.sh input_size_lex alpha"
   echo "e.g.:  common/train_joint_morfessor_segmentation.sh 300 2"
   echo "main options (for others, see top of script file)"
   echo "    --cmd (run.pl|queue.pl...)      # specify how to run the sub-processes."
   exit 1;
fi

lex_size=$1
alpha=$2

name=morphjoin_${lex_size}_${alpha}

dir=data/segmentation/$name
mkdir -p $dir
mkdir -p data/dicts/$name

cut -f1 data/text/topwords | common/filter_lex.py data-prep/lexicon/lexicon.txt - - /dev/null | head -n${lex_size}000 | morfessjoint-train -t - -x $dir/outlex -s $dir/morfessor.bin -S $dir/morfessor.txt

last=$(cat data/text/split/numjobs)

mkdir -p $dir/{log,tmp}


$cmd JOB=1000:$last $dir/log/JOB.log morfessor-segment -e utf-8 -l $dir/model.bin data/text/split/JOB --output-newlines --output-format-separator="+ +" --output-format="{analysis} " \| sed "s#^\s*#<s> #g" \| sed "s/\s*$/ <\\/s>/g" \> ${dir}/tmp/JOB.out

grep -v "^#" $dir/model.txt | sed "s/ + /+ +/g" | tr ' ' '\n' | sort -u > $dir/vocab


cut -f1 $dir/outlex > $dir/lex_keys
cut -f2- $dir/outlex > $dir/lex_vals

cat $dir/outlex > $dir/tmp_lex

sed "s/^/+/g" < $dir/lex_keys | paste - $dir/lex_vals >> $dir/tmp_lex
sed "s/$/+/g" < $dir/lex_keys | paste - $dir/lex_vals >> $dir/tmp_lex
sed "s/^/+/g" < $dir/lex_keys | sed "s/$/+/g" | paste - $dir/lex_vals >> $dir/tmp_lex

common/filter_lex.py $dir/tmp_lex $dir/vocab $dir/tmp_lex2 $dir/oov
cat definitions/dict_prep/lex >> $dir/tmp_lex2
sort -u $dir/tmp_lex2 > data/dicts/$name/lexicon.txt
cp data/dict_train/*sil* data/dicts/$name/


cat $dir/tmp/* > corpus
rm -Rf $dir/tmp

#rm -Rf $dir/tmp_lex* $dir/lex_keys $dir/lex_vals
