#!/bin/bash
#
# Create a badge from an image
#
# Requirements:
#
# - inkscape
# - augeas
# - imagemagick
# - a badges directory with a template.svg and colors/ directory
#
# TODO:
# 
# - make badge fully SVG so color can be changed without a colors/ directory
# 

ILLUSTRATION="$1"
ORIG_SCRIPT=$(readlink -f "$0")
BIN_DIR=$(dirname "$ORIG_SCRIPT")
BADGES_DIR=$(dirname "$BIN_DIR")

while [ -z $TEXT ]; do
  TEXT=$(zenity --entry --title "Badge text" \
                --text "Enter badge text" \
                --entry-text $(basename "$ILLUSTRATION"))
  [ $? = 0 ] || exit
done

NAME=${TEXT//[ \/]/_}

while [ -z $SUBJECT ]; do
  SUBJECT=$(awk '{print $1}' $BADGES_DIR/colors/subjects.txt | \
            sort | \
            zenity --list --title "Badge subject" \
                   --text "Choose the badge subject" \
                   --column "Subject" --editable)
  [ $? = 0 ] || exit
done

_get_ill_attr() {
  local file="$1" attr="$2"
  local val=$(augtool -Ant "Xml incl $file" match "//*[#attribute/id='Illustration']/#attribute/${attr}" | \
              cut -d'=' -f2)
  echo $val
}


read COLOR TEXT_COLOR < <(awk "/^${SUBJECT} / {print \$2\" \"\$3}" $BADGES_DIR/colors/subjects.txt)

TEMPLATE="${BADGES_DIR}/template.svg"

ORIG_TEXT_STYLE=$(augtool -Ant "Xml incl $TEMPLATE" match "//*[#attribute/id='Text']/#attribute/style" | \
                  cut -d"=" -f2)

if [ -z $COLOR ]; then
  while [ -z $COLOR ]; do
    COLOR=$(ls $BADGES_DIR/colors/ | \
            sed -n '/\(.*\)_badge\.png/ s//\1/p' | sort | \
            zenity --list --title "Pick a color" \
                   --text "This subject is unknown, please pick a color"\
                   --column "Color")
    [ $? = 0 ] || exit
  done

  ORIG_TEXT_COLOR=$(echo "$ORIG_TEXT_STYLE" | \
                    cut -d"=" -f2 | \
                    sed -n "/.*fill:\([^;]\+\).*/ s//\1/p")
  while [ -z $TEXT_COLOR ]; do
    TEXT_COLOR=$(zenity --entry --title "Enter a text color" \
                        --text "This subject is unknown, please pick a text color"\
                        --entry-text "$ORIG_TEXT_COLOR")
    [ $? = 0 ] || exit
  done

  echo "$SUBJECT  $COLOR  $TEXT_COLOR" >> $BADGES_DIR/colors/subjects.txt
fi

while [ -z $STARS ]; do
  STARS=$(echo -e "No stars\n1\n2\n3\n4\n5\n" | \
               zenity --list --title "Stars" \
               --text "Select the number of stars" \
               --column "Number of stars")
  [ $? = 0 ] || exit
done

zenity --question --title "Display ribbon?" \
       --text "Do you want a ribbon?"
if [ $? = 0 ]; then
  RIBBON_CODE=""
else
  RIBBON_CODE="rm //*[#attribute/id='Ribbon']"
fi

while [ -z $DPI ]; do
  DPI=$(zenity --entry --title "Select DPI" \
               --text "Enter the desired DPI" --entry-text "300")
  [ $? = 0 ] || exit
done

mkdir -p "${BADGES_DIR}/${SUBJECT}"

SVG_FILE="${BADGES_DIR}/${SUBJECT}/${NAME}.svg"
PNG_FILE="${BADGES_DIR}/${SUBJECT}/${NAME}.png"

# Get orig size in template for illustration
ILL_ORIG_W=$(_get_ill_attr "$TEMPLATE" "width")
ILL_ORIG_H=$(_get_ill_attr "$TEMPLATE" "height")
ILL_ORIG_Y=$(_get_ill_attr "$TEMPLATE" "y")

# Get new size of target illustration
read ILL_W ILL_H < <(identify -format "%W %H" "$ILLUSTRATION")

let "ILL_TARGET_H = $ILL_ORIG_W * $ILL_H / $ILL_W"
let "ILL_TARGET_Y = $ILL_ORIG_Y - ($ILL_TARGET_H - $ILL_ORIG_H)/2"

ILL_PATH="file://$(readlink -f ${ILLUSTRATION})"
BADGE_PATH="file://$(readlink -f $BADGES_DIR/colors/${COLOR}_badge.png)"

TEXT_STYLE=$(echo $ORIG_TEXT_STYLE | sed -e "/fill:\([^;]\+\)/ s//fill:${TEXT_COLOR}/")

if [ "x${STARS}" = "xNo stars" ]; then
  STARS_CODE="rm //*[#attribute/inkscape:label='Star']"
elif [ "x${STARS}" != "x5" ]; then
  let "stars_start=${STARS}+1"
  for i in $(seq $stars_start 5); do
    STARS_CODE="${STARS_CODE}rm //*[#attribute/id='StarBright${i}']
"
  done
fi

echo "
set //*[#attribute/id='Text']/textPath/#text '${TEXT}'
set //*[#attribute/id='Text']/#attribute/style '${TEXT_STYLE}'
set //*[#attribute/id='Illustration']/#attribute/xlink:href '${ILL_PATH}'
set //*[#attribute/id='Illustration']/#attribute/height '${ILL_TARGET_H}' 
set //*[#attribute/id='Illustration']/#attribute/y '${ILL_TARGET_Y}' 
set //*[#attribute/id='Badge']/#attribute/xlink:href '${BADGE_PATH}'
${STARS_CODE}
${RIBBON_CODE}
save
errors
 " | augtool -Asnt "Xml.lns incl $TEMPLATE"

mv "${TEMPLATE}.augnew" $SVG_FILE
inkscape $SVG_FILE -D -e $PNG_FILE -d $DPI

eog $PNG_FILE
