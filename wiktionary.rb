#!/usr/bin/env ruby
# encoding: utf-8
require 'open-uri'
require 'json'
require 'cgi'
require 'unicode'
require 'digest'

endpoint_uri = "http://vi.wiktionary.org/w/api.php?format=json&action=query&list=categorymembers&cmpageid=86684&cmlimit=500&cmcontinue="

continue = nil
words = []
count = 0

# Prepare cache
if !Dir.exists?("cache")
  Dir.mkdir("cache")
end

begin
  current_page_link = endpoint_uri + CGI::escape(continue.to_s)
  current_page_md5 = Digest::MD5.hexdigest(current_page_link)
  if !File.exists?("cache/#{current_page_md5}")
    File.write("cache/#{current_page_md5}", open(current_page_link).read)
  end
  result = JSON.parse(open("cache/#{current_page_md5}").read)

  begin
    continue = result["query-continue"]["categorymembers"]["cmcontinue"]
  rescue NoMethodError
    continue = nil
  end
  count += result["query"]["categorymembers"].each do |page|
    words += page["title"].split(/[, -:–]/).reject do |word|
      word.length <= 1 || word.match(/[áắấéếíóốớúứýàằầèềìòồờùừỳảẳẩẻểỉỏổởủửỷãẵẫẽễĩõỗỡũữỹạặậẹệịọộợụựỵaăâeêioôơuưy]/).nil?
    end.map{|word| Unicode::downcase(word)}
  end.count
  print "\r#{count}"
end while continue

# Store words to file
print "\n"
File.write('words.txt', words.uniq!.join("\n"))
system("sort words.txt -o words.txt")
system("wc -l words.txt")

# Categorize words
unmarkeds = []
acutes = []
graves = []
hooks = []
tildes = []
dots = []

words.each do |word|
  case word
  when /[áắấéếíóốớúứý]/
    acutes << word
  when /[àằầèềìòồờùừỳ]/
    graves << word
  when /[ảẳẩẻểỉỏổởủửỷ]/
    hooks << word
  when /[ãẵẫẽễĩõỗỡũữỹ]/
    tildes << word
  when /[ạặậẹệịọộợụựỵ]/
    dots << word
  else
    unmarkeds << word
  end
end

File.write('words-unmarkeds.txt', unmarkeds.join("\n"))
system("sort words-unmarkeds.txt -o words-unmarkeds.txt")
system("wc -l words-unmarkeds.txt")

File.write('words-acutes.txt', acutes.join("\n"))
system("sort words-acutes.txt -o words-acutes.txt")
system("wc -l words-acutes.txt")

File.write('words-graves.txt', graves.join("\n"))
system("sort words-graves.txt -o words-graves.txt")
system("wc -l words-graves.txt")

File.write('words-hooks.txt', hooks.join("\n"))
system("sort words-hooks.txt -o words-hooks.txt")
system("wc -l words-hooks.txt")

File.write('words-tildes.txt', tildes.join("\n"))
system("sort words-tildes.txt -o words-tildes.txt")
system("wc -l words-tildes.txt")

File.write('words-dots.txt', dots.join("\n"))
system("sort words-dots.txt -o words-dots.txt")
system("wc -l words-dots.txt")