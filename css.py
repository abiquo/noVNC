#!/usr/bin/env python
import cssutils
from cssutils import CSSParser

parser = CSSParser()
css = parser.parseFile("./include/base.css")

for rule in css:
  if rule.type == rule.STYLE_RULE:
    if rule.selectorText == ".noVNC-buttons-right":
      if rule.style["float"]:
        # newstyle = re.sub(r'right:*px', "right: 50px", rule.style)
        rule.style['right'] = '50px'
    if rule.selectorText == "#noVNC_controls":
      rule.style['right'] = '62px'
    if rule.selectorText == "#noVNC_settings":
      rule.style['right'] = '70px'

css_file = open("./include/base.css", "w")
css_file.write(css.cssText)
css_file.close()
