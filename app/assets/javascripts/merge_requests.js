var MergeRequest = { 
  diffs_loaded: false,
  commits_loaded: false,

  init:
    function() { 
      $(".tabs a").live("click", function() { 
        $(".tabs a").parent().removeClass("active");
        $(this).parent().addClass("active");
      });

      $(".tabs a.merge-notes-tab").live("click", function() { 
        $(".merge-request-diffs").hide();
        $(".merge-request-notes").show();
      });

      $(".tabs a.merge-diffs-tab").live("click", function() { 
        if(!MergeRequest.diffs_loaded) { 
          MergeRequest.loadDiff(); 
        }
        $(".merge-request-notes").hide();
        $(".merge-request-diffs").show();
      });
    },

  loadDiff:
    function() { 
      $(".dashboard-loader").show();
      $.ajax({
        type: "GET",
        url: $(".merge-diffs-tab").attr("data-url"),
        complete: function(){ 
          MergeRequest.diffs_loaded = true;
          $(".merge-request-notes").hide();
          $(".dashboard-loader").hide()},
        dataType: "script"});
    }
}
