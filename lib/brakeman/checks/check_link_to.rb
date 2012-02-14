require 'brakeman/checks/check_cross_site_scripting'

#Checks for calls to link_to in versions of Ruby where link_to did not
#escape the first argument.
#
#See https://rails.lighthouseapp.com/projects/8994/tickets/3518-link_to-doesnt-escape-its-input
class Brakeman::CheckLinkTo < Brakeman::CheckCrossSiteScripting
  Brakeman::Checks.add self

  @description = "Checks for XSS in link_to in versions before 3.0"

  def run_check
    return unless version_between?("2.0.0", "2.9.9") and not tracker.config[:escape_html]

    @ignore_methods = Set.new([:button_to, :check_box, :escapeHTML, :escape_once,
                           :field_field, :fields_for, :h, :hidden_field,
                           :hidden_field, :hidden_field_tag, :image_tag, :label,
                           :mail_to, :radio_button, :select,
                           :submit_tag, :text_area, :text_field,
                           :text_field_tag, :url_encode, :url_for,
                           :will_paginate] ).merge tracker.options[:safe_methods]

    @known_dangerous = []
    #Ideally, I think this should also check to see if people are setting
    #:escape => false
    methods = tracker.find_call :target => false, :method => :link_to 

    @models = tracker.models.keys
    @inspect_arguments = tracker.options[:check_arguments]

    methods.each do |call|
      process_result call
    end
  end

  def process_result result
    #Have to make a copy of this, otherwise it will be changed to
    #an ignored method call by the code above.
    call = result[:call] = result[:call].dup

    return if call[3][1].nil?

    @matched = false
    process_link_text(call[3][1], result)
    @matched = false
    process_link_href(call[3][2], result)
  end

  def process_link_href(call, result)
    # temporarily remove because of different context, refactor
    swap = @ignore_methods.clone
    @ignore_methods.reject!{|item| [:h, :escapeHTML].include? item}
    @ignore_methods = @ignore_methods.merge(tracker.options[:url_safe_methods])

    second_arg = process call

    # rename or don't reuse, confusing
    process_link_text(second_arg, result, 'Unsafe', 'link_to href')

    # add it for other tests
    @ignore_methods = swap
  end

  def process_link_text(call, result, adjective = 'Unescaped', target = 'link_to')
    first_arg = process call
    type, match = has_immediate_user_input? first_arg

    if type
      case type
      when :params
        message = "#{adjective} parameter value in #{target}"
      when :cookies
        message = "#{adjective} cookie value in #{target}"
      else
        message = "#{adjective} user input value in #{target}"
      end

      unless duplicate? result
        add_result result
        warn :result => result,
          :warning_type => "Cross Site Scripting", 
          :message => message,
          :confidence => CONFIDENCE[:high]
      end

    elsif not tracker.options[:ignore_model_output] and match = has_immediate_model?(first_arg)
      method = match[2]
      
      unless duplicate? result or IGNORE_MODEL_METHODS.include? method
        add_result result

        if MODEL_METHODS.include? method or method.to_s =~ /^find_by/
          confidence = CONFIDENCE[:high]
        else
          confidence = CONFIDENCE[:med]
        end
        warn :result => result,
          :warning_type => "Cross Site Scripting", 
          :message => "#{adjective} model attribute in #{target}",
          :confidence => confidence
      end

    elsif @matched
      
      if @matched == :model and not tracker.options[:ignore_model_output]
        message = "#{adjective} model attribute in #{target}"
      elsif @matched == :params
        message = "#{adjective} parameter value in #{target}"
      end

      if message and not duplicate? result
        add_result result
      
        warn :result => result, 
          :warning_type => "Cross Site Scripting", 
          :message => message,
          :confidence => CONFIDENCE[:med]
      end
    end
  end

  def process_call exp
    @mark = true
    actually_process_call exp
    exp
  end

  def actually_process_call exp
    return if @matched

    target = exp[1]
    if sexp? target
      target = process target.dup
    end

    #Bare records create links to the model resource,
    #not a string that could have injection
    if model_name? target and context == [:call, :arglist]
      return exp
    end

    super
  end
end
