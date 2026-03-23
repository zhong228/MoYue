package io.legado.app.model.analyzeRule

import java.io.File

fun main(args: Array<String>) {
    require(args.size >= 2) { "usage: legado_compare <htmlPath> <rule>" }
    val html = File(args[0]).readText()
    val rule = args[1]
    val analyzer = AnalyzeByJSoup(html)
    val content = analyzer.getString(rule) ?: ""
    val list = analyzer.getStringList(rule)

    println("CONTENT_LEN=${content.length}")
    println("CONTENT_PREVIEW=${content.take(500)}")
    println("LIST_COUNT=${list.size}")
    list.take(20).forEach { println("ITEM=$it") }
}
