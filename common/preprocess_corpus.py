#!/usr/bin/env python3
import argparse
import codecs
import lzma
import sys
import unicodedata


def preprocess_corpus(inf, outf):
    for line in lzma.open(inf, 'rt', encoding='utf-8'):
        if line.startswith("FILE"):
            continue

        sent = []

        for w in line.lower().strip().split():
            if not any(unicodedata.category(c).startswith("L") for c in w):
                continue
            sent.append(w)

        if len(sent) == 0:
            continue

        if sent[0] != "<s>":
            sent = ["<s>"] + sent
        if sent[-1] != "</s>":
            sent.append("</s>")

        if len(sent) < 3:
            continue

        print(" ".join(sent), file=outf)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='')
    parser.add_argument('infile', nargs='?', type=argparse.FileType('rb'), default=sys.stdin.buffer)
    parser.add_argument('outfile', nargs='?', type=argparse.FileType('w', encoding='utf-8'), default=codecs.getwriter('utf-8')(sys.stdout.buffer))

    args = parser.parse_args()

    preprocess_corpus(args.infile, args.outfile)