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
numjobs=50

numjobs=$(cat data/test_kth/spk2utt | wc -l)

job dec_mono0a 6 40 NONE \
 -- steps/decode.sh --nj ${numjobs} --cmd "$decode_cmd" exp/mono0a/graph_nst_2g_120k data/test_kth exp/mono0a/decode_2g_120k_test_kth
job dec_bl_mono0a 6 40 NONE \
 -- steps/decode_biglm.sh --nj ${numjobs} --cmd "$decode_cmd"  exp/mono0a/graph_nst_2g_120k data/120k_2gram/G.fst data/120k_5gram/G.fst data/test_kth exp/mono0a/decode_2g_120k_test_kth_biglm_5g
job dec_rs_mono0a 6 40 dec_mono0a \
 -- steps/lmrescore.sh --cmd "$decode_cmd" data/120k_2gram data/120k_5gram data/test_kth exp/mono0a/decode_2g_120k_test_kth exp/mono0a/decode_2g_120k_test_kth_rescore_5g

for model in "tri1" "tri2a" "tri2b"; do
    job dec_${model} 6 40 NONE \
     -- steps/decode.sh --nj ${numjobs} --cmd "$decode_cmd" exp/${model}/graph_nst_2g_120k data/test_kth exp/${model}/decode_2g_120k_test_kth
    job dec_bl_${model} 6 40 NONE \
     -- steps/decode_biglm.sh --nj ${numjobs} --cmd "$decode_cmd"  exp/${model}/graph_nst_2g_120k data/120k_2gram/G.fst data/120k_5gram/G.fst data/test_kth exp/${model}/decode_2g_120k_test_kth_biglm_5g
    job dec_rs_${model} 6 40 dec_${model} \
     -- steps/lmrescore.sh --cmd "$decode_cmd" data/120k_2gram data/120k_5gram data/test_kth exp/${model}/decode_2g_120k_test_kth exp/${model}/decode_2g_120k_test_kth_rescore_5g
done

for model in "tri3b" "tri4a" "tri4b"; do
    job mkg_${model} 26 40 NONE \
     -- utils/mkgraph.sh data/120k_2gram exp/${model} exp/${model}/graph_nst_2g_120k
    job dec_${model} 6 40 LAST \
     -- steps/decode_fmllr.sh --nj ${numjobs} --cmd "$decode_cmd" exp/${model}/graph_nst_2g_120k data/test_kth exp/${model}/decode_2g_120k_test_kth
    job dec_rs_${model} 6 40 dec_${model} \
     -- steps/lmrescore.sh --cmd "$decode_cmd" data/120k_2gram data/120k_5gram data/test_kth exp/${model}/decode_2g_120k_test_kth exp/${model}/decode_2g_120k_test_kth_rescore_5g
done