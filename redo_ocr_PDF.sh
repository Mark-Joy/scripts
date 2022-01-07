#!/usr/bin/env bash

datestring=`date +%Y-%m-%d_%H.%M.%S`
dir_path=$(dirname $0)
# Get length so final finalname is not too long
ldate=`echo ${#datestring}`
maxl=`expr 255 - $ldate`
tmpdir=`echo $TMPDIR`
keepfirst=false
lang='eng'

# Read flags
# Provide help if no argument
if [[ $# == 0 ]]
then
    set -- "-h"
fi

while test $# -gt 0; do
  case "$1" in
    -h|--help)
      echo ""
      echo "This script will remove existing text in a PDF and then perform OCR and"
      echo "add that text to it the original."
      echo ""
      echo "Usage: redo_ocr_PDF [options] filename [ocrmypdf (optimize) options]"
      echo "options:"
      echo "-h, --help     Show this brief help."
      echo "-f, --first    Keep the first page of the original PDF."
      echo "-l language    Use this language for OCR (defaults to English)"
      echo "-o, --opt      Enable PDF optimization. Pass (optimize) options (such as --rotate-pages --deskew --jbig2-lossy) after input filename"
      echo "               Use one of tesserat's 3-letter codes for this"
      exit 0
      ;;
    -f|--first)
      shift
      first=true
      ;;
    -l)
      shift
      lang=$1
      shift
      ;;
    -o|--opt)
      shift
      opt=true
      ;;
    *)
      break
      ;;
  esac
done

input="$1"
input_extension="${1##*.}"

if [[ "$1" == "" ]]
then
  echo "\aYou must enter a filename."
  exit 0
fi

# Make sure $1 is shifted out
shift

# Make sure file exists
if [[ ! -s "$input" ]]
then
  echo ''
  echo "\a"File \""$input"\" does not appear to exist or has no content! Exiting...
  echo ''
  exit 0
fi

# Make sure it's a PDF
if [[ $input_extension != 'pdf' ]]
then
  echo ''
  echo -e "\a"File "$input" does not appear to be a PDF. Exiting...
  echo ''
  exit 0
fi

# Check for language. Easy to forget to specify.
# Needs some error checking
if [[ -z $lang ]]
then
	printf "\n"
    read -p 'No language was specified. Hit enter to use English or supply the 3-letter language code: ' langInput
    printf "\n"
    if [[ -z $langInput ]]
    then
        lang='eng'
    else
        lang=$langInput
    fi
fi

# Get final output file name
final=`basename "$input"`
final="${final%.*}-ocr.pdf"
## final="${final:0:$maxl}"
## final="$final"_"$datestring".pdf
origdir=`dirname "$input"`

# Get some of the original document metadata to add back at the end
title=`pdfinfo "$input" | grep ^Title: | perl -pe 's/Title:\s+//'`
author=`pdfinfo "$input" | grep ^Author: | perl -pe 's/Author:\s+//'`

# If desired, remove the first page right away and save a little time
if [[ $first ]]
then
  inputold="$input"
  input="$tmpdir"input_new.pdf
  qpdf "$inputold" --pages . 2-z -- "$input"
fi

if [[ $opt ]]; then
	input_opt="$tmpdir/input_opt.pdf"
	# optimize original pdf before ocr
	ocrmypdf --skip-text "$input" "$input_opt" --lang="$lang" "$@"
	input="$input_opt"
fi

# strip text from the PDF
python3 "$dir_path/remove_PDF_text.py" "$input" "$tmpdir/no_text.pdf"
#gs -o "$tmpdir/no_text.pdf" -dFILTERTEXT -sDEVICE=pdfwrite "$input"

# Make sure output file exists
if [[ ! -s "$tmpdir/no_text.pdf" ]]
then
  echo ''
  echo "\a"Work file \""$input"\" does not appear to exist or has no content! Exiting...
  echo ''
  exit 0
fi


# ocr the original pdf
ocrmypdf --force-ocr --pdf-renderer=hocr --output-type pdf -l $lang "$tmpdir/no_text.pdf" "$tmpdir/ocr_output.pdf"

#strip images from that result
gs -o "$tmpdir/textonly.pdf" -dFILTERIMAGE -dFILTERVECTOR -sDEVICE=pdfwrite "$tmpdir/ocr_output.pdf"

# overlay ocr text on file stripped of text
qpdf "$tmpdir/no_text.pdf" --overlay "$tmpdir/textonly.pdf" -- "$tmpdir/final.pdf"

# Restore the original metadata, if any
if [ "$title" != '' ]
then
  exiftool -Title="$title" "$tmpdir/final.pdf"
fi
if [ "$author" != '' ]
then
  exiftool -Author="$author" "$tmpdir/final.pdf"
fi

# replace first page if required
if [ $first ]
then
  qpdf "$tmpdir/final.pdf" --pages "$inputold" 1 . 1-z -- "$origdir"/"$final"
else
  mv "$tmpdir/final.pdf" "$origdir"/"$final"
fi

terminal-notifier -message "Your OCR is complete." -title "Yay!" -sound default
