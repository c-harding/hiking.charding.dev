#!/usr/bin/env ruby

require 'net/http'
require 'net/https'

cname = File.read('CNAME').strip
graph = URI.parse("https://graph.facebook.com/")

Dir['**/*.html'].each do |file|
  path = "https://#{cname}/#{file.sub(/(index)?\.html$/,'')}"

  https = Net::HTTP.new(graph.host,graph.port)
  https.use_ssl = true
  puts "Resetting Facebook cache for #{path}"
  uri = graph
  res = https.post(graph.path,
    URI.encode_www_form(id: path, scrape: true, access_token: ENV['FB_TOKEN']))
  if res.is_a? Net::HTTPSuccess
    puts "Reset Facebook cache for #{path}"
  else
    puts "Cannot reset Facebook cache for #{path}"
    puts res.body
  end
end