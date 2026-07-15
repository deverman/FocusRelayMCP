#!/usr/bin/env ruby
# Checks relative Markdown links without fetching the network.

missing = []
Dir.glob("**/*.md", File::FNM_DOTMATCH).reject { |path| path.start_with?(".build/") }.each do |path|
  text = File.read(path)
  text.scan(/\[[^\]]*\]\(([^)]+)\)/).flatten.each do |raw_target|
    target = raw_target.strip.sub(/^</, "").sub(/>$/, "").split("#", 2).first
    next if target.nil? || target.empty? || target.match?(/\A(?:https?:|mailto:|\/)/)

    decoded = target.gsub(/%20/, " ")
    resolved = File.expand_path(decoded, File.dirname(path))
    missing << "#{path}: #{raw_target}" unless File.exist?(resolved)
  end
end

unless missing.empty?
  warn "Broken relative Markdown links:"
  missing.each { |item| warn "- #{item}" }
  exit 1
end

puts "Relative Markdown links are valid."
