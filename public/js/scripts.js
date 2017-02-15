$(function(){
var catchCommandKeys= [];
$(document).keypress(function(e) {
   if (e.which == 109) {
      catchCommandKeys = [];
   } else {
      catchCommandKeys.push(e.which);
   }
   if (e.which == 99) {
      if (catchCommandKeys.toString() == "49,49,99") {
         alert("asdf");
      }
      console.log(catchCommandKeys.toString());
   }
   var characters = {48 : 0, 49 : 1, 50 : 2, 51 : 3, 52 : 4, 53 : 5, 54 : 6, 55 : 7, 56 : 8, 57 : 9, 45 : "-"};
   if (e.which == 111) {
      catchCommandKeys.pop();
      var commandKeys = [];
      for (item of catchCommandKeys) {
         commandKeys.push(characters[item]);
      }
      var mapId = commandKeys.join("");
      if (mapId.split("-").length == 2) {
         var rootNodeId = mapId.split("-")[1];
         var mapId = mapId.split("-")[0];
         $("#mmaps td.link1[mapId='" + mapId + "']").parent().find("table.rootNodes td[rootNodeIndex='" + rootNodeId + "'] span").click();
      } else {
         $("#mmaps td.link1[mapId='" + mapId + "'] span").click();
      }
   }
   if (e.which == 115) {
      catchCommandKeys.pop();
      var commandKeys = [];
      for (item of catchCommandKeys) {
         commandKeys.push(characters[item]);
      }
      var mapId = commandKeys.join("");
      if (mapId.split("-").length == 2) {
         var rootNodeId = mapId.split("-")[1];
         var mapId = mapId.split("-")[0];
         var position = $("#mmaps td.link1[mapId='" + mapId + "']").parent().find("table.rootNodes td[rootNodeIndex='" + rootNodeId + "'] span").position();
         var positionX = position.left;
         var positionY = position.top;
         window.scroll(positionX, positionY - 40);
      } else {
         var positionY = $("#mmaps td.link1[mapId='" + mapId + "'] span").position().top;
         window.scroll(0, positionY - 40);
      }
   }
});
$.ajax({
   url: "/ajaxRootLinks",
   method: "GET"
}).
done(function(msg) {
   hash = $.parseJSON(msg);
   $(".lastRoots").each(function() {
      var rootLinksBlock = $(this);
      var mapFile = $(this).attr("mapFile");
      if (mapFile in hash) {
         hash[mapFile].reverse().forEach(function(item) {
            var rootLink = $("[mapFile='"+mapFile+"'][class='mmRootNodeLink").filter(function() {
               return $(this).text().replace(/\n/g,"") == item.replace(/\n/g,"");
            });
            var rootLink = rootLink.clone();

            var rootLinkLine = rootLink.text().substring(0,8);
            rootLink.text(rootLinkLine);

            rootLink.appendTo(rootLinksBlock);
            rootLinksBlock.append("<br>");
            rootLink.click(function() {
               $.get(rootLink.attr("href"));
            });
         });
      }
   });
});
function supAlert(ths) {
   var mapFile = $(ths).attr("mapFile");
   var rootLine = $(ths).text();
   var msg = ""
   $.ajax({
      url: "/ajaxRootLinksSave",
      method: "GET",
      data: {mapFile: mapFile, line : rootLine}
   }).
   done(function(msg) {
      var rootLinksBlock = $("[class='lastRoots'][mapFile='"+mapFile+"']");
      rootLinksBlock.children().each(function(){
         $(this).remove();
      });
      hash = $.parseJSON(msg);
      hash[mapFile].reverse().forEach(function(item) {
         //var rootLink = $("[mapFile='"+mapFile+"']span:contains('"+item+"')");
         var rootLink = $("[mapFile='"+mapFile+"'][class='mmRootNodeLink").filter(function() {
            return $(this).text().replace(/\n/g,"") == item.replace(/\n/g,"");
         });
         var rootLink = rootLink.clone();

         var rootLinkLine = rootLink.text().substring(0,8);
         rootLink.text(rootLinkLine);

         rootLink.appendTo(rootLinksBlock);
         rootLinksBlock.append("<br>");
         rootLink.click(function() {
            $.get(rootLink.attr("href"));
         });
      });
   });
   $.get($(ths).attr("href"));
}
$(".mmFileLink").click(function() {
   $.get($(this).attr("href"));
});
$(".mmThemeLink").click(function() {
   $.get($(this).attr("href"));
});
$(".mmRootNodeLink").click(function() {
   var ths = this
   supAlert(ths);
});
$(".plansThemeLink").click(function() {
   $.get($(this).attr("href"));
});
var sortColumns = [
"mapNumber",
"mapName",
"nodesNumber",
"linksNumber",
"directory",
"pagesInBookCountNumber",
"readPagesInBookCountNumber",
"leafReadPagesInBookCountNumber",
"nonReadPagesNumber",
"editTime",
"commentsCol"
];
var sortState = {};
for (sC of sortColumns) {
   sortState[sC] = false;
   $("#" + sC).click(function() {
      var colName = $(this).attr("id");
      var l = $("#mmaps .map");
      l.each(function() {console.log($(this).find("td[class^='" + colName + "']").text())});
      l.each(function() {$(this).detach();});
      l = $(l.get().sort(function(a,b){
         start = $(a).find("td[class^='" + colName + "']").text();
         if (/^\d+$/.test(start)) start = parseInt(start);
         end = $(b).find("td[class^='" + colName + "']").text();
         if (/^\d+$/.test(end)) end = parseInt(end);
         return start > end;
      }));
      if (sortState[colName]) {
         l = $(l.get().reverse());
      }
      sortState[colName] = !sortState[colName];
      l.each(function() {$("#mmaps tr:first").after($(this));});
   });
}
});

//# vim: tabstop=4 softtabstop=0 noexpandtab shiftwidth=4 number
