#!/usr/bin/env ruby

puts `build/html.rb`
File.rename '.deploy.gitignore', '.gitignore'
