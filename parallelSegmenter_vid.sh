#!/bin/sh
#parallelSegmenter - Batch clipping videos with common start and end frames
echo
echo "======================================================================================"
echo "parallelSegmenter - Batch clipping videos with common start and end frames in parallel"
echo "======================================================================================"
echo

#Make an output dir
if [[ ! -d output/ ]]; then
	mkdir output
fi

segmenter () {
	local forkedID=$(printf 'seg%x\n' "$RANDOM")
	local tempDir="${forkedID}_temp"
	local movie="$1"
	local log="output/$(basename "$movie" .mp4).txt"
	local totalFrames=""
	local startRange=""
	local endRange=""
	local metric=""
	local adjustedStart=""
	local adjustedEnd=""

	echo "$forkedID::$movie"

	#Make a clean temp dir
	if [[ -d $tempDir ]]; then
		rm -rf $tempDir
		mkdir $tempDir
	else
		mkdir $tempDir
	fi

	#Generate frames for comparison
	echo "$forkedID::Making thumbnails..."
	ffmpeg -loglevel panic -i "$movie" -q:v 2 -vf scale=400:-1 -f image2 $tempDir/%d.jpg

	#Set a search range for the start and end points	
	echo "$forkedID::Finding start and end frames..."
	totalFrames=$(ls -l $tempDir | wc -l)
	totalFrames=$(expr $totalFrames - 1)
	startRange=$(echo "scale=0; ($totalFrames*.20)/1" | bc)
	endRange=$(echo "scale=0; ($totalFrames*.80)/1" | bc)

	#Get the latest frame that matches Start Frame - 1 (in case Start Frame is black)
	for i in $(seq 1 $startRange); do 
		frame="$tempDir/$i.jpg"
		metric=$(compare -metric MAE "$frame" tests/start.jpg null: 2>&1 | awk '{ print $1 }')
		metric=$(echo "scale=0; $metric/1" | bc)
		if [[ "$metric" -lt 1000 ]]; then
			#Add 1 (to get frame number of Start Frame) and convert to timecode in format ss.xxx
			adjustedStart=$(echo "scale=2; ($i + 1)/(24000/1001)" | bc)
			echo "start $adjustedStart" > "$log"
			break
		fi
	done

	#Get the latest frame that matches End Frame
	for i in $(seq $endRange $totalFrames); do 
		frame="$tempDir/$i.jpg"
		metric=$(compare -metric MAE "$frame" tests/end.jpg null: 2>&1 | awk '{ print $1 }')
		metric=$(echo "scale=0; $metric/1" | bc)
		if [[ "$metric" -lt 1000 ]]; then
			#Convert to timecode in format ss.xx
			adjustedEnd=$(echo "scale=2; ($i - 2)/(24000/1001)" | bc)
			echo "end $adjustedEnd" >> "$log"
		fi
	done
	echo "$forkedID::Start: $adjustedStart    End: $adjustedEnd"
	echo "$forkedID::Saving segmented clip..."
	#Clip out the segment we want
	ffmpeg -loglevel panic -i "$movie" -ss $adjustedStart -to $adjustedEnd -c:v libx264 -crf 16 -tune animation -level 41 -c:a copy -movflags faststart -y output/"$movie" && echo "$forkedID::Clip saved!" && rm -rf "$tempDir"
}

export -f segmenter
filelist=""
for movie in *.mp4; do
	filelist+="segmenter '$movie'\n"
done

echo "$filelist" | parallel -u


