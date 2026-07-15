#!/bin/bash
# count_words.sh — Count unique words in a text file
# Usage: ./count_words.sh <filename>

if [ -z "$1" ]; then
    echo "Usage: $0 <filename>"
    exit 1
fi

if [ ! -f "$1" ]; then
    echo "Error: File '$1' not found"
    exit 1
fi

echo "=== Word Frequency Analysis ==="
echo "File: $1"
echo

# Count unique words and sort by frequency (descending)
cat "$1" \
  | tr -s '[:space:]' '\n' \
  | sort \
  | uniq -c \
  | sort -rn \
  | head -20

echo
total_unique=$(cat "$1" | tr -s '[:space:]' '\n' | sort | uniq | wc -l)
total_words=$(cat "$1" | wc -w)

echo "Total unique words: ${total_unique}"
echo "Total words:        ${total_words}"
