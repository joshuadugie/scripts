#!/bin/bash

# This script downloads a URL list (by default contained within "list.txt"),
# saves each generated PDF to the web page's title, then combines them all, in
# order, into a combined PDF.

# An example "list.txt" contents are:
#   https://developer.chrome.com/apps/about_apps
#   https://developer.chrome.com/apps/first_app
#   https://developer.chrome.com/apps/app_architecture
#   https://developer.chrome.com/apps/app_lifecycle


URL_LIST="./list.txt"
URL_LIST="`readlink -f \"${URL_LIST}\"`"
dos2unix ${URL_LIST}
TMPDIR="`mktemp -d`"
ORIGDIR="`pwd`"
PDF_ARRAY=()

# loop through all the URLs, save to a PDF
pushd "${TMPDIR}" &>/dev/null
while IFS= read -r aline; do
    TITLE="`curl -kis \"${aline}\" | grep \<title\> | sed 's/<title> *\([^<]\+\)<\/title>/\1/g'`"
    TITLE="`echo ${TITLE}`"
    echo "Downloading \"${aline}\" to \"${TITLE}.pdf\""
    # wkhtmltopdf saves to a PDF
    /usr/bin/wkhtmltopdf -s Letter "$aline" tmp.pdf &>/dev/null
    # add a bookmark via pdftk, which will be preserved by ghostscript later
    pdftk tmp.pdf dump_data_utf8 output tmp.info
    echo "BookmarkTitle: ${TITLE}" >> tmp.info
    echo "BookmarkLevel: 1" >> tmp.info
    echo "BookmarkPageNumber: 1" >> tmp.info
    pdftk tmp.pdf update_info_utf8 tmp.info output "${TITLE}.pdf"
    PDF_ARRAY+=("${TITLE}.pdf")
    rm tmp.pdf tmp.info
done < "${URL_LIST}"

# finally, combine all the PDFs to a single one
echo ghostscript -sDEVICE=pdfwrite -o combined.pdf "${PDF_ARRAY[@]}"
ghostscript -sDEVICE=pdfwrite -o combined.pdf "${PDF_ARRAY[@]}"

# cleanup
mv combined.pdf "${ORIGDIR}"/
popd &>/dev/null
rm -fr "${TMPDIR}"
