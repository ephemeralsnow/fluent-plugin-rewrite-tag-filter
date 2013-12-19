require 'helper'

class RewriteTagFilterOutputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  CONFIG = %[
    rewriterule1 domain ^www\.google\.com$ site.Google
    rewriterule2 domain ^news\.google\.com$ site.GoogleNews
    rewriterule3 agent .* Mac OS X .* agent.MacOSX
    rewriterule4 agent (Googlebot|CustomBot)-([a-zA-Z]+) agent.$1-$2
    rewriterule5 domain ^(tagtest)\.google\.com$ site.${tag}.$1
  ]

  # aggresive test
  # indentation, comment, capitalize_regex_backreference, regex with space aside.
  # [DEPLICATED] Use ^....$ pattern for partial word match instead of double-quote-delimiter.
  CONFIG_INDENT_SPACE_AND_CAPITALIZE_OPTION = %[
    capitalize_regex_backreference yes
    rewriterule1 domain ^www\.google\.com$                  site.Google # some comment
    rewriterule2 domain ^(news)\.(google)\.com$             site.$2$1
    rewriterule3 agent  ^.* Mac OS X .*$                    agent.MacOSX
    rewriterule4 agent  "(Googlebot|CustomBot)-([a-zA-Z]+)" agent.$1-$2
  ]

  # remove_tag_prefix test
  CONFIG_REMOVE_TAG_PREFIX = %[
    rewriterule1 domain ^www\.google\.com$ ${tag}
    remove_tag_prefix input
  ]

  # remove_tag_prefix test2
  CONFIG_REMOVE_TAG_PREFIX_WITH_DOT = %[
    rewriterule1 domain ^www\.google\.com$ ${tag}
    remove_tag_prefix input.
  ]

  # hostname placeholder test
  CONFIG_SHORT_HOSTNAME = %[
    rewriterule1 domain ^www\.google\.com$ ${hostname}
    remove_tag_prefix input
    hostname_command hostname -s
  ]

  # '!' character (exclamation mark) to specify a non-matching pattern
  CONFIG_NON_MATCHING = %[
    rewriterule1 domain !^www\..+$ not_start_with_www
    rewriterule2 domain ^www\..+$ start_with_www
  ]

  # jump of index
  CONFIG_JUMP_INDEX = %[
    rewriterule10 domain ^www\.google\.com$ site.Google
    rewriterule20 domain ^news\.google\.com$ site.GoogleNews
  ]

  # split by tag
  CONFIG_SPLIT_BY_TAG = %[
    rewriterule1 user_name ^Lynn Minmay$ vip.${tag_parts[1]}.remember_love
    rewriterule2 user_name ^Harlock$ ${tag_parts[2]}.${tag_parts[0]}.${tag_parts[1]}
    rewriterule3 world ^(alice|chaos)$ application.${tag_parts[0]}.$1_server
    rewriterule4 world ^[a-z]+$ application.${tag_parts[1]}.future_server
  ]

  # test for invalid byte sequence in UTF-8 error
  CONFIG_INVALID_BYTE = %[
    rewriterule1 client_name (.+) app.$1
  ]

  # lexicographically precedes
  CONFIG_STR_LT_MATCHING = %[
    rewriterule1 alphabet -ltB lt_B
    rewriterule2 alphabet -ltC lt_C
  ]

  # lexicographically precedes or equal
  CONFIG_STR_LE_MATCHING = %[
    rewriterule1 alphabet -leB le_B
    rewriterule2 alphabet -leC le_C
  ]

  # lexicographically follows
  CONFIG_STR_GT_MATCHING = %[
    rewriterule1 alphabet -gtC gt_C
    rewriterule2 alphabet -gtB gt_B
  ]

  # lexicographically follows or equal
  CONFIG_STR_GE_MATCHING = %[
    rewriterule1 alphabet -geC ge_C
    rewriterule2 alphabet -geB ge_B
  ]

  # lexicographically equal
  CONFIG_STR_EQ_MATCHING = %[
    rewriterule1 alphabet -eqB eq_B
    rewriterule2 alphabet -eqC eq_C
  ]

  # not lexicographically precedes
  CONFIG_STR_NOT_LT_MATCHING = %[
    rewriterule1 alphabet !-ltC nlt_C
    rewriterule2 alphabet !-ltB nlt_B
  ]

  # not lexicographically precedes or equal
  CONFIG_STR_NOT_LE_MATCHING = %[
    rewriterule1 alphabet !-leC nle_C
    rewriterule2 alphabet !-leB nle_B
  ]

  # not lexicographically follows
  CONFIG_STR_NOT_GT_MATCHING = %[
    rewriterule1 alphabet !-gtB ngt_B
    rewriterule2 alphabet !-gtC ngt_C
  ]

  # not lexicographically follows or equal
  CONFIG_STR_NOT_GE_MATCHING = %[
    rewriterule1 alphabet !-geB nge_B
    rewriterule2 alphabet !-geC nge_C
  ]

  # not lexicographically equal
  CONFIG_STR_NOT_EQ_MATCHING = %[
    rewriterule1 alphabet !-eqB neq_B
  ]

  # numerically less than
  CONFIG_INT_LT_MATCHING = %[
    rewriterule1 number <2 lt_2
    rewriterule2 number <3 lt_3
  ]

  # numerically less than or equal
  CONFIG_INT_LE_MATCHING = %[
    rewriterule1 number <=2 le_2
    rewriterule2 number <=3 le_3
  ]

  # numerically greater than
  CONFIG_INT_GT_MATCHING = %[
    rewriterule1 number >3 gt_3
    rewriterule2 number >2 gt_2
  ]

  # numerically greater than or equal
  CONFIG_INT_GE_MATCHING = %[
    rewriterule1 number >=3 ge_3
    rewriterule2 number >=2 ge_2
  ]

  # numerically equal
  CONFIG_INT_EQ_MATCHING = %[
    rewriterule1 number =2 eq_2
    rewriterule2 number =3 eq_3
  ]

  # not numerically less than
  CONFIG_INT_NOT_LT_MATCHING = %[
    rewriterule1 number !<3 nlt_3
    rewriterule2 number !<2 nlt_2
  ]

  # not numerically less than or equal
  CONFIG_INT_NOT_LE_MATCHING = %[
    rewriterule1 number !<=3 nle_3
    rewriterule2 number !<=2 nle_2
  ]

  # not numerically greater
  CONFIG_INT_NOT_GT_MATCHING = %[
    rewriterule1 number !>2 ngt_2
    rewriterule2 number !>3 ngt_3
  ]

  # not numerically greater or equal
  CONFIG_INT_NOT_GE_MATCHING = %[
    rewriterule1 number !>=2 nge_2
    rewriterule2 number !>=3 nge_3
  ]

  # not numerically equal
  CONFIG_INT_NOT_EQ_MATCHING = %[
    rewriterule1 number !=2 neq_2
  ]

  def create_driver(conf=CONFIG,tag='test')
    Fluent::Test::OutputTestDriver.new(Fluent::RewriteTagFilterOutput, tag).configure(conf)
  end

  def test_configure
    assert_raise(Fluent::ConfigError) {
      d = create_driver('')
    }
    assert_raise(Fluent::ConfigError) {
      d = create_driver('rewriterule1 foo')
    }
    assert_raise(Fluent::ConfigError) {
      d = create_driver('rewriterule1 foo foo')
    }
    assert_raise(Fluent::ConfigError) {
      d = create_driver('rewriterule1 hoge hoge.${tag_parts[0..2]}.__TAG_PARTS[0..2]__')
    }
    assert_raise(Fluent::ConfigError) {
      d = create_driver('rewriterule1 fuga fuga.${tag_parts[1...2]}.__TAG_PARTS[1...2]__')
    }
    d = create_driver %[
      rewriterule1 domain ^www.google.com$ site.Google
      rewriterule2 domain ^news.google.com$ site.GoogleNews
    ]
    assert_equal 'domain ^www.google.com$ site.Google', d.instance.config['rewriterule1']
    assert_equal 'domain ^news.google.com$ site.GoogleNews', d.instance.config['rewriterule2']
  end

  def test_emit
    d1 = create_driver(CONFIG, 'input.access')
    d1.run do
      d1.emit({'domain' => 'www.google.com', 'path' => '/foo/bar?key=value', 'agent' => 'Googlebot', 'response_time' => 1000000})
      d1.emit({'domain' => 'news.google.com', 'path' => '/', 'agent' => 'Googlebot-Mobile', 'response_time' => 900000})
      d1.emit({'domain' => 'map.google.com', 'path' => '/', 'agent' => 'Macintosh; Intel Mac OS X 10_7_4', 'response_time' => 900000})
      d1.emit({'domain' => 'labs.google.com', 'path' => '/', 'agent' => 'Mozilla/5.0 Googlebot-FooBar/2.1', 'response_time' => 900000})
      d1.emit({'domain' => 'tagtest.google.com', 'path' => '/', 'agent' => 'Googlebot', 'response_time' => 900000})
      d1.emit({'domain' => 'noop.example.com'}) # to be ignored
    end
    emits = d1.emits
    assert_equal 5, emits.length
    assert_equal 'site.Google', emits[0][0] # tag
    assert_equal 'site.GoogleNews', emits[1][0] # tag
    assert_equal 'news.google.com', emits[1][2]['domain']
    assert_equal 'agent.MacOSX', emits[2][0] #tag
    assert_equal 'agent.Googlebot-FooBar', emits[3][0] #tag
    assert_equal 'site.input.access.tagtest', emits[4][0] #tag
  end

  def test_emit02_indent_and_capitalize_option
    d1 = create_driver(CONFIG_INDENT_SPACE_AND_CAPITALIZE_OPTION, 'input.access')
    d1.run do
      d1.emit({'domain' => 'www.google.com', 'path' => '/foo/bar?key=value', 'agent' => 'Googlebot', 'response_time' => 1000000})
      d1.emit({'domain' => 'news.google.com', 'path' => '/', 'agent' => 'Googlebot-Mobile', 'response_time' => 900000})
      d1.emit({'domain' => 'map.google.com', 'path' => '/', 'agent' => 'Macintosh; Intel Mac OS X 10_7_4', 'response_time' => 900000})
      d1.emit({'domain' => 'labs.google.com', 'path' => '/', 'agent' => 'Mozilla/5.0 Googlebot-FooBar/2.1', 'response_time' => 900000})
    end
    emits = d1.emits
    assert_equal 4, emits.length
    assert_equal 'site.Google', emits[0][0] # tag
    assert_equal 'site.GoogleNews', emits[1][0] # tag
    assert_equal 'news.google.com', emits[1][2]['domain']
    assert_equal 'agent.MacOSX', emits[2][0] #tag
    assert_equal 'agent.Googlebot-Foobar', emits[3][0] #tag
  end

  def test_emit03_remove_tag_prefix
    d1 = create_driver(CONFIG_REMOVE_TAG_PREFIX, 'input.access')
    d1.run do
      d1.emit({'domain' => 'www.google.com', 'path' => '/foo/bar?key=value', 'agent' => 'Googlebot', 'response_time' => 1000000})
    end
    emits = d1.emits
    assert_equal 1, emits.length
    assert_equal 'access', emits[0][0] # tag
  end

  def test_emit04_remove_tag_prefix_with_dot
    d1 = create_driver(CONFIG_REMOVE_TAG_PREFIX_WITH_DOT, 'input.access')
    d1.run do
      d1.emit({'domain' => 'www.google.com', 'path' => '/foo/bar?key=value', 'agent' => 'Googlebot', 'response_time' => 1000000})
    end
    emits = d1.emits
    assert_equal 1, emits.length
    assert_equal 'access', emits[0][0] # tag
  end

  def test_emit05_short_hostname
    d1 = create_driver(CONFIG_SHORT_HOSTNAME, 'input.access')
    d1.run do
      d1.emit({'domain' => 'www.google.com', 'path' => '/foo/bar?key=value', 'agent' => 'Googlebot', 'response_time' => 1000000})
    end
    emits = d1.emits
    assert_equal 1, emits.length
    assert_equal `hostname -s`.chomp, emits[0][0] # tag
  end

  def test_emit06_non_matching
    d1 = create_driver(CONFIG_NON_MATCHING, 'input.access')
    d1.run do
      d1.emit({'domain' => 'www.google.com'})
      d1.emit({'path' => '/'})
      d1.emit({'domain' => 'maps.google.com'})
    end
    emits = d1.emits
    assert_equal 3, emits.length
    assert_equal 'start_with_www', emits[0][0] # tag
    assert_equal 'not_start_with_www', emits[1][0] # tag
    assert_equal 'not_start_with_www', emits[2][0] # tag
  end

  def test_emit07_jump_index
    d1 = create_driver(CONFIG_JUMP_INDEX, 'input.access')
    d1.run do
      d1.emit({'domain' => 'www.google.com', 'path' => '/', 'agent' => 'Googlebot', 'response_time' => 1000000})
      d1.emit({'domain' => 'news.google.com', 'path' => '/', 'agent' => 'Googlebot', 'response_time' => 900000})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 'site.Google', emits[0][0] # tag
    assert_equal 'site.GoogleNews', emits[1][0] # tag
  end

  def test_emit08_split_by_tag
    d1 = create_driver(CONFIG_SPLIT_BY_TAG, 'game.production.api')
    d1.run do
      d1.emit({'user_id' => '10000', 'world' => 'chaos', 'user_name' => 'gamagoori'})
      d1.emit({'user_id' => '10001', 'world' => 'chaos', 'user_name' => 'sanageyama'})
      d1.emit({'user_id' => '10002', 'world' => 'nehan', 'user_name' => 'inumuta'})
      d1.emit({'user_id' => '77777', 'world' => 'space', 'user_name' => 'Lynn Minmay'})
      d1.emit({'user_id' => '99999', 'world' => 'space', 'user_name' => 'Harlock'})
    end
    emits = d1.emits
    assert_equal 5, emits.length
    assert_equal 'application.game.chaos_server', emits[0][0]
    assert_equal 'application.game.chaos_server', emits[1][0]
    assert_equal 'application.production.future_server', emits[2][0]
    assert_equal 'vip.production.remember_love', emits[3][0]
    assert_equal 'api.game.production', emits[4][0]
  end

  def test_emit09_invalid_byte
    invalid_utf8 = "\xff".force_encoding('UTF-8')
    d1 = create_driver(CONFIG_INVALID_BYTE, 'input.activity')
    d1.run do
      d1.emit({'client_name' => invalid_utf8})
    end
    emits = d1.emits
    assert_equal 1, emits.length
    assert_equal "app.?", emits[0][0]
    assert_equal invalid_utf8, emits[0][2]['client_name']

    invalid_ascii = "\xff".force_encoding('US-ASCII')
    d1 = create_driver(CONFIG_INVALID_BYTE, 'input.activity')
    d1.run do
      d1.emit({'client_name' => invalid_ascii})
    end
    emits = d1.emits
    assert_equal 1, emits.length
    assert_equal "app.?", emits[0][0]
    assert_equal invalid_ascii, emits[0][2]['client_name']
  end

  def test_emit10_lexicographically_precedes
    d1 = create_driver(CONFIG_STR_LT_MATCHING, 'alphabets')
    d1.run do
      d1.emit({'alphabet' => 'A'})
      d1.emit({'alphabet' => 'B'})
      d1.emit({'alphabet' => 'C'})
      d1.emit({'alphabet' => 'D'})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 'A', emits[0][2]['alphabet']
    assert_equal 'lt_B', emits[0][0]
    assert_equal 'B', emits[1][2]['alphabet']
    assert_equal 'lt_C', emits[1][0]
  end

  def test_emit11_lexicographically_precedes_or_equal
    d1 = create_driver(CONFIG_STR_LE_MATCHING, 'alphabets')
    d1.run do
      d1.emit({'alphabet' => 'A'})
      d1.emit({'alphabet' => 'B'})
      d1.emit({'alphabet' => 'C'})
      d1.emit({'alphabet' => 'D'})
    end
    emits = d1.emits
    assert_equal 3, emits.length
    assert_equal 'A', emits[0][2]['alphabet']
    assert_equal 'le_B', emits[0][0]
    assert_equal 'B', emits[1][2]['alphabet']
    assert_equal 'le_B', emits[1][0]
    assert_equal 'C', emits[2][2]['alphabet']
    assert_equal 'le_C', emits[2][0]
  end

  def test_emit12_lexicographically_follows
    d1 = create_driver(CONFIG_STR_GT_MATCHING, 'alphabets')
    d1.run do
      d1.emit({'alphabet' => 'A'})
      d1.emit({'alphabet' => 'B'})
      d1.emit({'alphabet' => 'C'})
      d1.emit({'alphabet' => 'D'})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 'C', emits[0][2]['alphabet']
    assert_equal 'gt_B', emits[0][0]
    assert_equal 'D', emits[1][2]['alphabet']
    assert_equal 'gt_C', emits[1][0]
  end

  def test_emit13_lexicographically_follows_or_equal
    d1 = create_driver(CONFIG_STR_GE_MATCHING, 'alphabets')
    d1.run do
      d1.emit({'alphabet' => 'A'})
      d1.emit({'alphabet' => 'B'})
      d1.emit({'alphabet' => 'C'})
      d1.emit({'alphabet' => 'D'})
    end
    emits = d1.emits
    assert_equal 3, emits.length
    assert_equal 'B', emits[0][2]['alphabet']
    assert_equal 'ge_B', emits[0][0]
    assert_equal 'C', emits[1][2]['alphabet']
    assert_equal 'ge_C', emits[1][0]
    assert_equal 'D', emits[2][2]['alphabet']
    assert_equal 'ge_C', emits[2][0]
  end

  def test_emit14_lexicographically_equal
    d1 = create_driver(CONFIG_STR_EQ_MATCHING, 'alphabets')
    d1.run do
      d1.emit({'alphabet' => 'A'})
      d1.emit({'alphabet' => 'B'})
      d1.emit({'alphabet' => 'C'})
      d1.emit({'alphabet' => 'D'})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 'B', emits[0][2]['alphabet']
    assert_equal 'eq_B', emits[0][0]
    assert_equal 'C', emits[1][2]['alphabet']
    assert_equal 'eq_C', emits[1][0]
  end

  def test_emit15_not_lexicographically_precedes
    d1 = create_driver(CONFIG_STR_NOT_LT_MATCHING, 'alphabets')
    d1.run do
      d1.emit({'alphabet' => 'A'})
      d1.emit({'alphabet' => 'B'})
      d1.emit({'alphabet' => 'C'})
      d1.emit({'alphabet' => 'D'})
    end
    emits = d1.emits
    assert_equal 3, emits.length
    assert_equal 'B', emits[0][2]['alphabet']
    assert_equal 'nlt_B', emits[0][0]
    assert_equal 'C', emits[1][2]['alphabet']
    assert_equal 'nlt_C', emits[1][0]
    assert_equal 'D', emits[2][2]['alphabet']
    assert_equal 'nlt_C', emits[2][0]
  end

  def test_emit16_not_lexicographically_precedes_or_equal
    d1 = create_driver(CONFIG_STR_NOT_LE_MATCHING, 'alphabets')
    d1.run do
      d1.emit({'alphabet' => 'A'})
      d1.emit({'alphabet' => 'B'})
      d1.emit({'alphabet' => 'C'})
      d1.emit({'alphabet' => 'D'})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 'C', emits[0][2]['alphabet']
    assert_equal 'nle_B', emits[0][0]
    assert_equal 'D', emits[1][2]['alphabet']
    assert_equal 'nle_C', emits[1][0]
  end

  def test_emit17_not_lexicographically_follows
    d1 = create_driver(CONFIG_STR_NOT_GT_MATCHING, 'alphabets')
    d1.run do
      d1.emit({'alphabet' => 'A'})
      d1.emit({'alphabet' => 'B'})
      d1.emit({'alphabet' => 'C'})
      d1.emit({'alphabet' => 'D'})
    end
    emits = d1.emits
    assert_equal 3, emits.length
    assert_equal 'A', emits[0][2]['alphabet']
    assert_equal 'ngt_B', emits[0][0]
    assert_equal 'B', emits[1][2]['alphabet']
    assert_equal 'ngt_B', emits[1][0]
    assert_equal 'C', emits[2][2]['alphabet']
    assert_equal 'ngt_C', emits[2][0]
  end

  def test_emit18_not_lexicographically_follows_or_equal
    d1 = create_driver(CONFIG_STR_NOT_GE_MATCHING, 'alphabets')
    d1.run do
      d1.emit({'alphabet' => 'A'})
      d1.emit({'alphabet' => 'B'})
      d1.emit({'alphabet' => 'C'})
      d1.emit({'alphabet' => 'D'})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 'A', emits[0][2]['alphabet']
    assert_equal 'nge_B', emits[0][0]
    assert_equal 'B', emits[1][2]['alphabet']
    assert_equal 'nge_C', emits[1][0]
  end

  def test_emit19_not_lexicographically_equal
    d1 = create_driver(CONFIG_STR_NOT_EQ_MATCHING, 'alphabets')
    d1.run do
      d1.emit({'alphabet' => 'A'})
      d1.emit({'alphabet' => 'B'})
      d1.emit({'alphabet' => 'C'})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 'A', emits[0][2]['alphabet']
    assert_equal 'neq_B', emits[0][0]
    assert_equal 'C', emits[1][2]['alphabet']
    assert_equal 'neq_B', emits[1][0]
  end

  def test_emit20_numerically_less_than
    d1 = create_driver(CONFIG_INT_LT_MATCHING, 'numbers')
    d1.run do
      d1.emit({'number' => 1})
      d1.emit({'number' => 2})
      d1.emit({'number' => 3})
      d1.emit({'number' => 4})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 1, emits[0][2]['number']
    assert_equal 'lt_2', emits[0][0]
    assert_equal 2, emits[1][2]['number']
    assert_equal 'lt_3', emits[1][0]
  end

  def test_emit21_numerically_less_than_or_equal
    d1 = create_driver(CONFIG_INT_LE_MATCHING, 'numbers')
    d1.run do
      d1.emit({'number' => 1})
      d1.emit({'number' => 2})
      d1.emit({'number' => 3})
      d1.emit({'number' => 4})
    end
    emits = d1.emits
    assert_equal 3, emits.length
    assert_equal 1, emits[0][2]['number']
    assert_equal 'le_2', emits[0][0]
    assert_equal 2, emits[1][2]['number']
    assert_equal 'le_2', emits[1][0]
    assert_equal 3, emits[2][2]['number']
    assert_equal 'le_3', emits[2][0]
  end

  def test_emit22_numerically_greater_than
    d1 = create_driver(CONFIG_INT_GT_MATCHING, 'numbers')
    d1.run do
      d1.emit({'number' => 1})
      d1.emit({'number' => 2})
      d1.emit({'number' => 3})
      d1.emit({'number' => 4})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 3, emits[0][2]['number']
    assert_equal 'gt_2', emits[0][0]
    assert_equal 4, emits[1][2]['number']
    assert_equal 'gt_3', emits[1][0]
  end

  def test_emit23_numerically_greater_than_or_equal
    d1 = create_driver(CONFIG_INT_GE_MATCHING, 'numbers')
    d1.run do
      d1.emit({'number' => 1})
      d1.emit({'number' => 2})
      d1.emit({'number' => 3})
      d1.emit({'number' => 4})
    end
    emits = d1.emits
    assert_equal 3, emits.length
    assert_equal 2, emits[0][2]['number']
    assert_equal 'ge_2', emits[0][0]
    assert_equal 3, emits[1][2]['number']
    assert_equal 'ge_3', emits[1][0]
    assert_equal 4, emits[2][2]['number']
    assert_equal 'ge_3', emits[2][0]
  end

  def test_emit24_numerically_equal
    d1 = create_driver(CONFIG_INT_EQ_MATCHING, 'numbers')
    d1.run do
      d1.emit({'number' => 1})
      d1.emit({'number' => 2})
      d1.emit({'number' => 3})
      d1.emit({'number' => 4})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 2, emits[0][2]['number']
    assert_equal 'eq_2', emits[0][0]
    assert_equal 3, emits[1][2]['number']
    assert_equal 'eq_3', emits[1][0]
  end

  def test_emit25_not_numerically_less_than
    d1 = create_driver(CONFIG_INT_NOT_LT_MATCHING, 'numbers')
    d1.run do
      d1.emit({'number' => 1})
      d1.emit({'number' => 2})
      d1.emit({'number' => 3})
      d1.emit({'number' => 4})
    end
    emits = d1.emits
    assert_equal 3, emits.length
    assert_equal 2, emits[0][2]['number']
    assert_equal 'nlt_2', emits[0][0]
    assert_equal 3, emits[1][2]['number']
    assert_equal 'nlt_3', emits[1][0]
    assert_equal 4, emits[2][2]['number']
    assert_equal 'nlt_3', emits[2][0]
  end

  def test_emit26_not_numerically_less_than_or_equal
    d1 = create_driver(CONFIG_INT_NOT_LE_MATCHING, 'numbers')
    d1.run do
      d1.emit({'number' => 1})
      d1.emit({'number' => 2})
      d1.emit({'number' => 3})
      d1.emit({'number' => 4})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 3, emits[0][2]['number']
    assert_equal 'nle_2', emits[0][0]
    assert_equal 4, emits[1][2]['number']
    assert_equal 'nle_3', emits[1][0]
  end

  def test_emit27_not_numerically_greater_than
    d1 = create_driver(CONFIG_INT_NOT_GT_MATCHING, 'numbers')
    d1.run do
      d1.emit({'number' => 1})
      d1.emit({'number' => 2})
      d1.emit({'number' => 3})
      d1.emit({'number' => 4})
    end
    emits = d1.emits
    assert_equal 3, emits.length
    assert_equal 1, emits[0][2]['number']
    assert_equal 'ngt_2', emits[0][0]
    assert_equal 2, emits[1][2]['number']
    assert_equal 'ngt_2', emits[1][0]
    assert_equal 3, emits[2][2]['number']
    assert_equal 'ngt_3', emits[2][0]
  end

  def test_emit28_not_numerically_greater_than_or_equal
    d1 = create_driver(CONFIG_INT_NOT_GE_MATCHING, 'numbers')
    d1.run do
      d1.emit({'number' => 1})
      d1.emit({'number' => 2})
      d1.emit({'number' => 3})
      d1.emit({'number' => 4})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 1, emits[0][2]['number']
    assert_equal 'nge_2', emits[0][0]
    assert_equal 2, emits[1][2]['number']
    assert_equal 'nge_3', emits[1][0]
  end

  def test_emit29_not_numerically_equal
    d1 = create_driver(CONFIG_INT_NOT_EQ_MATCHING, 'numbers')
    d1.run do
      d1.emit({'number' => 1})
      d1.emit({'number' => 2})
      d1.emit({'number' => 3})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 1, emits[0][2]['number']
    assert_equal 'neq_2', emits[0][0]
    assert_equal 3, emits[1][2]['number']
    assert_equal 'neq_2', emits[1][0]
  end

end
