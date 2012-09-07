$(document).ready(function(){

  $(".one_click_select").live("click", function(){
    $(this).select();
  });

  $('body').on('ajax:complete, ajax:beforeSend, submit', 'form', function(e){
    var buttons = $('[type="submit"]', this);
    switch( e.type ){
      case 'ajax:beforeSend':
      case 'submit':
        buttons.attr('disabled', 'disabled');
      break;
      case ' ajax:complete':
      default:
        buttons.removeAttr('disabled');
      break;
    }
  })

  $(".account-box").mouseenter(showMenu);
  $(".account-box").mouseleave(resetMenu);

  $("#projects-list .project").live('click', function(e){
    if(e.target.nodeName != "A" && e.target.nodeName != "INPUT") {
      location.href = $(this).attr("url");
      e.stopPropagation();
      return false;
    }
  });

  /**
   * Focus search field by pressing 's' key
   */
  $(document).keypress(function(e) {
    if( $(e.target).is(":input") ) return;
    switch(e.which)  {
      case 115:  focusSearch();
        e.preventDefault();
    }
  });

  /**
   * Commit show suppressed diff
   *
   */
  $(".supp_diff_link").bind("click", function() {
    showDiff(this);
  });

  /**
   * Note markdown preview
   *
   */
  $(document).on('click', '#preview-link', function(e) {
    $('#preview-note').text('Loading...');

    var previewLinkText = ($(this).text() == 'Preview' ? 'Edit' : 'Preview');
    $(this).text(previewLinkText);

    var note = $('#note_note').val();
    if (note.trim().length === 0) { note = 'Nothing to preview'; }
    $.post($(this).attr('href'), {note: note}, function(data) {
      $('#preview-note').html(data);
    });

    $('#preview-note, #note_note').toggle();
    e.preventDefault();
  });
});

function focusSearch() {
  $("#search").focus();
}

function updatePage(data){
  $.ajax({type: "GET", url: location.href, data: data, dataType: "script"});
}

function showMenu() {
  $(this).toggleClass('hover');
}

function resetMenu() {
  $(this).removeClass("hover");
}

function slugify(text) {
  return text.replace(/[^-a-zA-Z0-9]+/g, '_').toLowerCase();
}

function showDiff(link) {
  $(link).next('table').show();
  $(link).remove();
}

(function($){
    var _chosen = $.fn.chosen;
    $.fn.extend({
        chosen: function(options) {
            var default_options = {'search_contains' : 'true'};
            $.extend(default_options, options);
            return _chosen.apply(this, [default_options]);
    }})
})(jQuery);


function ajaxGet(url) {
  $.ajax({type: "GET", url: url, dataType: "script"});
}

/**
 * Disable button if text field is empty
 */
function disableButtonIfEmtpyField(field_selector, button_selector) {
  field = $(field_selector);
  if(field.val() == "") {
    field.closest("form").find(button_selector).attr("disabled", "disabled").addClass("disabled");
  }

  field.on('keyup', function(){
    var field = $(this);
    var closest_submit = field.closest("form").find(button_selector);
    if(field.val() == "") {
      closest_submit.attr("disabled", "disabled").addClass("disabled");
    } else {
      closest_submit.removeAttr("disabled").removeClass("disabled");
    }
  })
}
