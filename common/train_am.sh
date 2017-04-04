#!/bin/bash

echo "$0 $@"  # Print the command line for logging
export LC_ALL=C

min_seg_len=1.55


[ -f path.sh ] && . ./path.sh # source the path.
. parse_options.sh || exit 1;

if [ $# != 0 ]; then
   echo "usage: train_am.sh"
   exit 1;
fi

. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.

train_cmd="srun run.pl"
base_cmd=$train_cmd
decode_cmd=$train_cmd

. common/slurm_dep_graph.sh

JOB_PREFIX=$(cat id)_

function error_exit {
    echo "$1" >&2
    exit "${2:-1}"
}

if [ ! -d "data-prep" ]; then
 error_exit "The directory data-prep needs to exist. Run local/data_prep.sh"
fi

#rm -Rf data mfcc
mkdir -p data tmp


lex_name="lexicon"
if [ -f definitions/lexicon ]; then
  lex_name=$(cat definitions/lexicon)
fi
ln -s ../data-prep/${lex_name}/ data/lexicon

job make_subset 1 1 NONE -- common/data_subset.sh
#job make_mc 1 1 LAST -- common/make_multichannel_data.sh data-prep/audio/wav.scp data/train data/train_mc

job make_lex 1 4 make_subset -- common/make_dict.sh data/train/vocab data/dict
job make_lang 1 4 make_lex -- utils/prepare_lang.sh --position-dependent-phones true data/dict "<UNK>" data/lang/local data/lang
job make_lang_pip 1 4 LAST -- utils/prepare_lang.sh --position-dependent-phones false data/dict "<UNK>" data/lang_pip/local data/lang_pip
job make_phone_map 1 1 LAST -- common/make_phone_map.sh data/lang data/lang_pip
job text_prep 1 24 NONE -- common/text_prep.sh

mfccdir=mfcc
numjobs=20

. definitions/best_model

# Extract low-res standard features
mkdir -p mfcc
command -v lfs > /dev/null && lfs setstripe -c 6 $mfccdir

for set in "train" "dev" "test"; do
 job mfcc_$set 1 4 make_subset -- steps/make_mfcc.sh --cmd "$mfcc_cmd" --nj ${numjobs} data/${set} exp/make_mfcc/${set} ${mfccdir}
 job cmvn_$set 1 4 LAST      -- steps/compute_cmvn_stats.sh data/${set} exp/make_mfcc/${set} ${mfccdir}
 job fix_data_$set 4 4 LAST  -- utils/fix_data_dir.sh data/${set}
 job val_data_$set 1 4 LAST  -- utils/validate_data_dir.sh data/${set}
 job utt2dur_$set 1 4 LAST   -- utils/data/get_utt2dur.sh data/${set}
done

#for set in "dev" "test"; do
# job copy_h_$set 1 4 utt2dur_$set -- utils/copy_data_dir.sh data/$set data/${set}_hires
# job mfcc_hires_$set 1 4 LAST     -- steps/make_mfcc.sh --mfcc-config conf/mfcc_hires.conf --cmd "$mfcc_cmd" --nj ${numjobs} data/${set}_hires
# job cmvn_hires_$set 1 4 LAST     -- steps/compute_cmvn_stats.sh data/${set}_hires
# job fix_hires_$set 4 4 LAST      -- utils/fix_data_dir.sh data/${set}_hires
# job val_data_${set}_hires 1 4 LAST -- utils/validate_data_dir.sh data/${set}_hires
#done

# Make short dir
numjobs=10
job subset_10kshort 1 4 utt2dur_train \
 -- utils/subset_data_dir.sh --shortest data/train ${sub_size:-10000} data/train_10kshort

# Train basic iterations
SLURM_EXTRA_ARGS="-c ${numjobs}"
job tra_mono 1 4 subset_10kshort,make_lang \
 -- steps/train_mono.sh --boost-silence 1.25 --nj ${numjobs} --cmd "$train_cmd" data/train_10kshort data/lang exp/mono

job ali_mono 1 4 tra_mono,val_data_train \
 -- steps/align_si.sh --boost-silence 1.25 --nj ${numjobs} --cmd "$train_cmd" data/train data/lang exp/mono exp/mono_ali

job tra_tri1 1 4 LAST \
 -- steps/train_deltas.sh --boost-silence 1.25 --cmd "$train_cmd" $tri1_leaves $tri1_gauss data/train data/lang exp/mono_ali exp/tri1

job ali_tri1 1 4 LAST \
 -- steps/align_si.sh --nj ${numjobs} --cmd "$train_cmd" data/train data/lang exp/tri1 exp/tri1_ali

job tra_tri2 1 4 LAST \
 -- steps/train_lda_mllt.sh --cmd "$train_cmd" --splice-opts "--left-context=3 --right-context=3" $tri2_leaves $tri2_gauss data/train data/lang exp/tri1_ali exp/tri2

job ali_tri2 1 4 LAST \
 -- steps/align_si.sh  --nj ${numjobs} --cmd "$train_cmd"  data/train data/lang exp/tri2 exp/tri2_ali

job tra_tri3 1 4 LAST \
 -- steps/train_sat.sh --cmd "$train_cmd" $tri3_leaves $tri3_gauss data/train data/lang exp/tri2_ali exp/tri3

job ali_tri3 1 4 LAST \
 -- steps/align_fmllr.sh  --nj ${numjobs} --cmd "$train_cmd"  data/train data/lang exp/tri3 exp/tri3_ali

# Train also version of tri3 with position-independent-phones
#job tra_tri3_pip 1 4 tra_tri3,make_phone_map \
# -- steps/train_sat.sh --cmd "$train_cmd" --phone-map data/lang_pip/phone_map $tri3_leaves $tri3_gauss data/train data/lang_pip exp/tri3 exp/tri3_pip



SLURM_EXTRA_ARGS=""
# Create a cleaned version of the model, which is supposed to be better for
job clean 2 4 tra_tri3 \
 -- steps/cleanup/clean_and_segment_data.sh --nj 200 --cmd "slurm.pl --mem 2G" data/train data/lang exp/tri3 exp/tri3_cleaned_work data/train_cleaned

SLURM_EXTRA_ARGS="-c ${numjobs}"
job ali_tri3_cleaned 2 4 LAST \
 -- steps/align_fmllr.sh --nj ${numjobs} --cmd "$train_cmd" data/train_cleaned data/lang exp/tri3 exp/tri3_ali_cleaned

job tra_tri3_cleaned 2 4 LAST \
 -- steps/train_sat.sh --cmd "$train_cmd" $tri3_leaves $tri3_gauss data/train_cleaned data/lang exp/tri3_ali_cleaned exp/tri3_cleaned

# Train also version of tri3 with position-independent-phones
#job tra_tri3_cleaned_pip 2 4 tra_tri3_cleaned \
# -- steps/train_sat.sh --cmd "$train_cmd" --phone-map data/lang_pip/phone_map $tri3_leaves $tri3_gauss data/train_cleaned data/lang_pip exp/tri3_cleaned exp/tri3_cleaned_pip

#SLURM_EXTRA_ARGS=""
#job make_cleaned_mc 1 1 clean -- common/make_multichannel_data.sh data-prep/audio/wav.scp data/train_cleaned data/train_cleaned_mc
#job utt2dur_train_cleaned_mc 1 4 LAST   -- utils/data/get_utt2dur.sh data/train_cleaned_mc

