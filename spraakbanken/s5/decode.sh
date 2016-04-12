#!/bin/bash

. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.

. ../../../util/slurm_dep_graph.sh

JOB_PREFIX=$(basename $(pwd))

function error_exit {
    echo "$1" >&2
    exit "${2:-1}"
}

mfccdir=mfcc
numjobs=10

numjobs=$(cat data/dev/spk2utt | wc -l)

echo "Changing numjobs to ${numjobs}"
job mkg_mono0a 26 40 NONE \
 -- utils/mkgraph.sh --mono data/20k_2gram exp/mono0a exp/mono0a/graph_nst_2g_20k
job dec_mono0a 6 40 LAST \
 -- steps/decode.sh --nj ${numjobs} --cmd "$decode_cmd" exp/mono0a/graph_nst_2g_20k data/dev exp/mono0a/decode_2g_20k_dev
job dec_bl_mono0a 6 40 mkg_mono0a \
 -- steps/decode_biglm.sh --nj ${numjobs} --cmd "$decode_cmd"  exp/mono0a/graph_nst_2g_20k data/20k_2gram/G.fst data/20k_5gram/G.fst data/dev exp/mono0a/decode_2g_20k_dev_biglm_5g
job dec_rs_mono0a 6 40 dec_mono0a \
 -- steps/lmrescore.sh --cmd "$decode_cmd" data/20k_2gram data/20k_5gram data/dev exp/mono0a/decode_2g_20k_dev exp/mono0a/decode_2g_20k_dev_rescore_5g

for model in "tri1" "tri2a" "tri2b"; do
    job mkg_${model} 26 40 NONE \
     -- utils/mkgraph.sh data/20k_2gram exp/${model} exp/${model}/graph_nst_2g_20k
    job dec_${model} 6 40 LAST \
     -- steps/decode.sh --nj ${numjobs} --cmd "$decode_cmd" exp/${model}/graph_nst_2g_20k data/dev exp/${model}/decode_2g_20k_dev
    job dec_bl_${model} 6 40 mkg_${model} \
     -- steps/decode_biglm.sh --nj ${numjobs} --cmd "$decode_cmd"  exp/${model}/graph_nst_2g_20k data/20k_2gram/G.fst data/20k_5gram/G.fst data/dev exp/${model}/decode_2g_20k_dev_biglm_5g
    job dec_rs_${model} 6 40 dec_${model} \
     -- steps/lmrescore.sh --cmd "$decode_cmd" data/20k_2gram data/20k_5gram data/dev exp/${model}/decode_2g_20k_dev exp/${model}/decode_2g_20k_dev_rescore_5g
done

for model in "tri3b" "tri4a" "tri4b"; do
    job mkg_${model} 26 40 NONE \
     -- utils/mkgraph.sh data/20k_2gram exp/${model} exp/${model}/graph_nst_2g_20k
    job dec_${model} 6 40 LAST \
     -- steps/decode_fmllr.sh --nj ${numjobs} --cmd "$decode_cmd" exp/${model}/graph_nst_2g_20k data/dev exp/${model}/decode_2g_20k_dev
done
