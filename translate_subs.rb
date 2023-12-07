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

  unless i
    puts("#{file} - no subtitle track")
    next
  end

  en_srt = "#{path.basename('.*')}.en.srt"
  en_ass = "#{path.basename('.*')}.en.ass"
  pt_srt = "#{path.basename('.*')}.srt"

  unless File.exist?(en_srt)
    if tracks.dig(i, 'Codec ID')&.include?('ASS')
      `mkvextract tracks #{Shellwords.escape(file)} #{i}:#{Shellwords.escape(en_ass)}`
      asstosrt(en_ass)
      `rm #{Shellwords.escape(en_ass)}`
    else
      `mkvextract tracks #{Shellwords.escape(file)} #{i}:#{Shellwords.escape(en_srt)}`
    end
  end

  # Join split lines for better translation
  srt = SRT::File.parse(File.new(en_srt))
  srt.to_s # make sure we didn't fail parsing

  total = srt.lines.size
  progress = 0
  srt.lines.each_slice(1) do |slice|
    slice.map { |l| Thread.new { l.text = [`trans -no-warn -no-autocorrect -brief en:pt-BR #{Shellwords.escape(l.text.join(' '))}`.to_s.strip] if l.text.join(' ').scan(/\w/).size > 1 } }.each(&:join)
    progress += slice.size
    printf("\r#{file} - %0.1f%%", progress * 100.0 / total)
  end
  printf("\r#{file} - %0.1f%%\n", 100.0)
  IO.write(pt_srt, srt.to_s)

  `rm #{Shellwords.escape(en_srt)}`
end
