#!/usr/bin/env ruby

processed = []

def parse_sass(input, output)
  result = system('sass', input, output)
  raise result unless $?.to_i == 0
  raise "When compiled the module should output some CSS" unless File.exists?(output)
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