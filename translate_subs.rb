#!/usr/bin/env ruby

# Ruby script to extract and translate subtitles from MKV files from English to Portuguese (but you can customize this)
#
# Dependencies:
#
#   1. `gem install srt`
#   2. `brew install translate-shell mkvtoolnix`
#
# Usage:
#
#   translate_subs [FILE]
#
# Notice: it assumes the subtitles are on a specific track index, which may change from file to file.
# Tracks can be checked using `mkvinfo file.mkv`

require 'shellwords'
require 'pathname'
require 'srt'
require 'pry'

require_relative 'asstosrt'

ARGV.each do |file|
  path = Pathname(file)

  tracks = []
  track = false
  `mkvinfo #{Shellwords.escape(file)}`.split("\n").each do |line|
    if line =~ /\+\sTrack\z/
      tracks << {}
      track = true
      next
    end

    if track && line =~ /\A|\s\s/
      match = line.match(/\+\s([^:]*):(.*)\z/)
      tracks.last[match[1].strip] = match[2].strip if match
      next
    end

    track = false
  end

  i = tracks.find_index { |t| t['Track type'] == 'subtitles' }

  en_srt = "#{path.basename('.*')}.en.srt"
  en_ass = "#{path.basename('.*')}.en.ass"
  pt_srt = "#{path.basename('.*')}.srt"


  if tracks.dig(i, 'Codec ID')&.include?('ASS')
    `mkvextract tracks #{Shellwords.escape(file)} #{i}:#{Shellwords.escape(en_ass)}`
    asstosrt(en_ass)
    `rm #{Shellwords.escape(en_ass)}`
  else
    `mkvextract tracks #{Shellwords.escape(file)} #{i}:#{Shellwords.escape(en_srt)}`
  end

  # Join split lines for better translation
  srt = SRT::File.parse(File.new(en_srt))
  total = srt.lines.size
  srt.lines.each_with_index do |l, idx|
    l.text = [`trans -no-warn -no-autocorrect -brief en:pt-BR #{Shellwords.escape(l.text.join(' '))}`.to_s.strip] if l.text.join(' ').size > 2
    printf("\r#{file} - %0.1f%%", (idx + 1) * 100.0 / total)
  end
  printf("\r#{file} - %0.1f%%", 100.0)
  IO.write(pt_srt, srt.to_s)

  `rm #{Shellwords.escape(en_srt)}`
end
