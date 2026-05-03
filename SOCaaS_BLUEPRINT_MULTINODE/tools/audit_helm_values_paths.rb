#!/usr/bin/env ruby
# Static audit for Helm .Values paths used in templates.
require 'yaml'
root = File.expand_path('..', __dir__)
values = YAML.load_file(File.join(root, 'charts/socaas/values.yaml'))
override = YAML.load_file(File.join(root, 'charts/socaas/values-multinode.yaml'))

def deep_merge(a, b)
  return a unless b.is_a?(Hash)
  a = a.dup
  b.each do |k, v|
    a[k] = a[k].is_a?(Hash) && v.is_a?(Hash) ? deep_merge(a[k], v) : v
  end
  a
end

merged = deep_merge(values, override)

def path_exists?(hash, path)
  cur = hash
  path.split('.').each do |part|
    return false unless cur.is_a?(Hash) && cur.key?(part)
    cur = cur[part]
  end
  true
end

paths = []
Dir.glob(File.join(root, 'charts/socaas/templates/**/*')).each do |file|
  next unless File.file?(file)
  txt = File.read(file)
  txt.scan(/\.Values\.([A-Za-z0-9_\.]+)/).flatten.each do |p|
    paths << p.sub(/\.+$/, '')
  end
end

missing = paths.uniq.sort.reject { |p| path_exists?(merged, p) }
if missing.empty?
  puts "OK: all Helm .Values paths exist"
else
  warn "Missing Helm values paths:"
  missing.each { |p| warn "  - #{p}" }
  exit 1
end
