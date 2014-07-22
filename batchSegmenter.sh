#!/bin/sh
#batchSegmenter - Batch clipping videos with common start and end frames
echo
echo "======================================================================="
echo "batchSegmenter - Batch clipping videos with common start and end frames"
echo "======================================================================="
echo

#Make an output dir
if [[ ! -d output/ ]]; then
	mkdir output
fi

for movie in *.mp4; do
	echo "Starting work on $movie..."
	#Clear all variables
	log="output/$(basename "$movie" .mp4).txt"
	totalFrames=""
	startRange=""
	endRange=""
	metric=""
	adjustedStart=""
	adjustedEnd=""

	#Make a clean temp dir
	if [[ -d temp/ ]]; then
		rm -rf temp
		mkdir temp
	else
		mkdir temp
	fi

	#Generate frames for comparison
	echo "Making thumbnails..."
	ffmpeg -loglevel panic -i "$movie" -q:v 2 -vf scale=400:-1 -f image2 temp/%d.jpg

	#find start and end
	echo "Finding start and end frames..."
	
	totalFrames=$(ls -l temp/ | wc -l)
	totalFrames=$(expr $totalFrames - 1)
	startRange=$(echo "scale=0; ($totalFrames*.20)/1" | bc)
	endRange=$(echo "scale=0; ($totalFrames*.80)/1" | bc)

	#Get the latest frame that matches Start Frame - 1 (in case Start Frame is black)
	for i in $(seq 1 $startRange); do 
		frame="temp/$i.jpg"
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
		frame="temp/$i.jpg"
		metric=$(compare -metric MAE "$frame" tests/end.jpg null: 2>&1 | awk '{ print $1 }')
		metric=$(echo "scale=0; $metric/1" | bc)
		if [[ "$metric" -lt 1000 ]]; then
			#Subtract a couple of frames to deal with ffmpeg's inaccuracy and convert to timecode in format ss.xx
			adjustedEnd=$(echo "scale=2; ($i - 2)/(24000/1001)" | bc)
			echo "end $adjustedEnd" >> "$log"
		fi
	done

	echo "     Start: $adjustedStart    End: $adjustedEnd"

	#Clip out the segment we want
	echo "Saving segmented clip..."
	ffmpeg -loglevel panic -i "$movie" -ss $adjustedStart -to $adjustedEnd -c:v libx264 -crf 16 -tune animation -c:a copy -movflags faststart -y output/"$movie" && echo "Clip saved!"
	echo
done