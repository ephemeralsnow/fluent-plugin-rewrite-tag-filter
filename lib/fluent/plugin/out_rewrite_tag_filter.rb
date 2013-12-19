class Fluent::RewriteTagFilterOutput < Fluent::Output
  Fluent::Plugin.register_output('rewrite_tag_filter', self)

  config_param :capitalize_regex_backreference, :bool, :default => false
  config_param :remove_tag_prefix, :string, :default => nil
  config_param :hostname_command, :string, :default => 'hostname'

  def initialize
    super
    require 'string/scrub'
  end

  def configure(conf)
    super

    @rewriterules = []
    rewriterule_names = []
    @hostname = `#{@hostname_command}`.chomp

    conf.keys.select{|k| k =~ /^rewriterule(\d+)$/}.sort_by{|i| i.sub('rewriterule', '').to_i}.each do |key|
      rewritekey,rewritecondition,rewritetag = parse_rewriterule(conf[key])
      if rewritecondition.nil? || rewritetag.nil?
        raise Fluent::ConfigError, "failed to parse rewriterules at #{key} #{conf[key]}"
      end

      unless rewritetag.match(/\$\{tag_parts\[\d\.\.\.?\d\]\}/).nil? or rewritetag.match(/__TAG_PARTS\[\d\.\.\.?\d\]__/).nil?
        raise Fluent::ConfigError, "${tag_parts[n]} and __TAG_PARTS[n]__ placeholder does not support range specify at #{key} #{conf[key]}"
      end

      include_backreference = !rewritetag.match(/\$\d+/).nil?
      include_placeholder = !rewritetag.match(/(\${[a-z_]+(\[[0-9]+\])?}|__[A-Z_]+__)/).nil?

      match_inverse,match_operator,match_value = parse_rewritecondition(rewritecondition)
      if match_operator != :match_operator_regexp && include_backreference
        raise Fluent::ConfigError, "comparison feature does not support backreference at #{key} #{conf[key]}"
      end

      @rewriterules.push([rewritekey, match_inverse, match_operator, match_value, rewritetag, include_backreference, include_placeholder])
      rewriterule_names.push(rewritekey + rewritecondition)
      $log.info "adding rewrite_tag_filter rule: #{key} #{@rewriterules.last}"
    end

    unless @rewriterules.length > 0
      raise Fluent::ConfigError, "missing rewriterules"
    end

    unless @rewriterules.length == rewriterule_names.uniq.length
      raise Fluent::ConfigError, "duplicated rewriterules found #{@rewriterules.inspect}"
    end

    unless @remove_tag_prefix.nil?
      @remove_tag_prefix = /^#{Regexp.escape(@remove_tag_prefix)}\.?/
    end
  end

  def emit(tag, es, chain)
    placeholder = get_placeholder(tag)
    es.each do |time,record|
      rewrited_tag = rewrite_tag(tag, record, placeholder)
      next if rewrited_tag.nil? || tag == rewrited_tag
      Fluent::Engine.emit(rewrited_tag, time, record)
    end

    chain.next
  end

  def rewrite_tag(tag, record, placeholder)
    @rewriterules.each do |rewritekey, match_inverse, match_operator, match_value, rewritetag, include_backreference, include_placeholder|
      rewritevalue = record[rewritekey]
      match_result = send(match_operator, rewritevalue, match_value) unless rewritevalue.nil?
      next unless !!match_result ^ match_inverse

      if include_backreference
        backreference_table = get_backreference_table(match_result.captures)
        rewritetag = rewritetag.gsub(/\$\d+/, backreference_table)
      end
      if include_placeholder
        rewritetag = rewritetag.gsub(/(\${[a-z_]+(\[[0-9]+\])?}|__[A-Z_]+__)/) do
          $log.warn "rewrite_tag_filter: unknown placeholder found. :placeholder=>#{$1} :tag=>#{tag} :rewritetag=>#{rewritetag}" unless placeholder.include?($1)
          placeholder[$1]
        end
      end
      return rewritetag
    end
    return nil
  end

  def regexp_last_match(regexp, rewritevalue)
    begin
      return if regexp.nil?
      regexp.match(rewritevalue)
      return $~
    rescue ArgumentError => e
      raise e unless e.message.index('invalid byte sequence in') == 0
      regexp.match(rewritevalue.scrub('?'))
      return $~
    end
  end

  def parse_rewriterule(rule)
    if rule.match(/^([^\s]+)\s+(.+?)\s+([^\s]+)$/)
      return $~.captures
    end
  end

  def parse_rewritecondition(condition)
    condition = trim_condition_quote(condition)
    scanner = StringScanner.new(condition)
    match_inverse = !!scanner.scan(/!/)
    match_operator, match_value =
      if scanner.scan(/\-(lt|le|gt|ge|eq|ne)/)
        match_value = scanner.post_match
        case scanner.matched
        when '-lt' then [:match_operator_str_lt, match_value]
        when '-le' then [:match_operator_str_le, match_value]
        when '-gt' then [:match_operator_str_gt, match_value]
        when '-ge' then [:match_operator_str_ge, match_value]
        when '-eq' then [:match_operator_str_eq, match_value]
        end
      elsif scanner.scan(/(<=|<|>=|>|=)/)
        match_value = scanner.post_match.to_i
        case scanner.matched
        when '<'  then [:match_operator_int_lt, match_value]
        when '<=' then [:match_operator_int_le, match_value]
        when '>'  then [:match_operator_int_gt, match_value]
        when '>=' then [:match_operator_int_ge, match_value]
        when '='  then [:match_operator_int_eq, match_value]
        end
      else
        regexp = scanner.rest
        [:match_operator_regexp, /#{regexp}/]
      end

    return [match_inverse, match_operator, match_value]
  end

  def trim_condition_quote(condition)
    if condition.start_with?('"') && condition.end_with?('"')
      $log.info "rewrite_tag_filter: [DEPRECATED] Use ^....$ pattern for partial word match instead of double-quote-delimiter. #{condition}"
      condition = condition[1..-2]
    end
    return condition
  end

  def get_backreference_table(elements)
    hash_table = Hash.new
    elements.each.with_index(1) do |value, index|
      hash_table["$#{index}"] = @capitalize_regex_backreference ? value.capitalize : value
    end
    return hash_table
  end

  def get_placeholder(tag)
    tag = tag.sub(@remove_tag_prefix, '') if @remove_tag_prefix

    result = {
      '__HOSTNAME__' => @hostname,
      '${hostname}' => @hostname,
      '__TAG__' => tag,
      '${tag}' => tag,
    }

    tag.split('.').each_with_index do |t, idx|
      result.store("${tag_parts[#{idx}]}", t)
      result.store("__TAG_PARTS[#{idx}]__", t)
    end

    return result
  end

  def match_operator_str_lt(rewritevalue, match_value); rewritevalue.to_s <  match_value end
  def match_operator_str_le(rewritevalue, match_value); rewritevalue.to_s <= match_value end
  def match_operator_str_gt(rewritevalue, match_value); rewritevalue.to_s >  match_value end
  def match_operator_str_ge(rewritevalue, match_value); rewritevalue.to_s >= match_value end
  def match_operator_str_eq(rewritevalue, match_value); rewritevalue.to_s == match_value end
  def match_operator_int_lt(rewritevalue, match_value); rewritevalue.to_i <  match_value end
  def match_operator_int_le(rewritevalue, match_value); rewritevalue.to_i <= match_value end
  def match_operator_int_gt(rewritevalue, match_value); rewritevalue.to_i >  match_value end
  def match_operator_int_ge(rewritevalue, match_value); rewritevalue.to_i >= match_value end
  def match_operator_int_eq(rewritevalue, match_value); rewritevalue.to_i == match_value end
  def match_operator_regexp(rewritevalue, regexp); regexp_last_match(regexp, rewritevalue.to_s) end

end
