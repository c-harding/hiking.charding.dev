#!/usr/bin/env ruby

require 'sassc'

processed = []

def parse_sass(input, output)
  sass = File.read(input)
  css = SassC::Engine.new(sass, style: :compressed, syntax: :sass).render

  File.write(output, css)
  puts "Built CSS to #{output}"
end

def parse(input)
  output, extension = input.match(/^(.+)\.([^\.]*)$/).captures
  case extension
  when "scss", "sass"
    parse_sass input, output
  when "css", "map"
    return
  else
    STDERR.puts "Unable to compile #{input}: unrecognised extension"
  end
  parse output
end

def files(&block)
  if ARGV.empty?
    Dir.glob '**/*.css.*' do |path|
      block[path]
    end
  else
    Dir.glob ARGV do |path|
      if path.match? /\.css\.(.*)$/
        block[path]
      else
        STDERR.puts "Not a CSS file: #{path}"
      end
    end
  end
end

files do |file|
  parse file
end
