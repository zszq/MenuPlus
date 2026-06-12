#!/usr/bin/env python3
"""生成右键菜单"新建文件"用的最小合法 OOXML 模板。

为什么用脚本生成而不是直接提交二进制：
- OOXML（docx/xlsx/pptx）本质是 zip + XML，空文件不是合法文档，
  必须包含最小的包结构（[Content_Types].xml、_rels、主部件）。
- 脚本让模板内容可审查、可复现；修改模板时改这里再重新生成。

输出：MenuPlus/Templates/Template.{docx,xlsx,pptx}
用法：python3 scripts/generate_office_templates.py
"""

import zipfile
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent.parent / "MenuPlus" / "Templates"

XML_DECL = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'

NS_CT = "http://schemas.openxmlformats.org/package/2006/content-types"
NS_REL_PKG = "http://schemas.openxmlformats.org/package/2006/relationships"
NS_REL_DOC = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
NS_A = "http://schemas.openxmlformats.org/drawingml/2006/main"
NS_P = "http://schemas.openxmlformats.org/presentationml/2006/main"
NS_W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
NS_S = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"


def rels(*entries: tuple[str, str, str]) -> str:
    items = "".join(
        f'<Relationship Id="{rid}" Type="{rtype}" Target="{target}"/>'
        for rid, rtype, target in entries
    )
    return f'{XML_DECL}<Relationships xmlns="{NS_REL_PKG}">{items}</Relationships>'


def content_types(overrides: dict[str, str]) -> str:
    parts = [
        f'<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
        '<Default Extension="xml" ContentType="application/xml"/>',
    ]
    parts += [
        f'<Override PartName="{name}" ContentType="{ctype}"/>'
        for name, ctype in overrides.items()
    ]
    return f'{XML_DECL}<Types xmlns="{NS_CT}">{"".join(parts)}</Types>'


def write_package(path: Path, parts: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, content in parts.items():
            zf.writestr(name, content)
    print(f"已生成 {path}")


def build_docx() -> dict[str, str]:
    document = (
        f'{XML_DECL}<w:document xmlns:w="{NS_W}"><w:body><w:p/>'
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/></w:sectPr>'
        "</w:body></w:document>"
    )
    return {
        "[Content_Types].xml": content_types({
            "/word/document.xml": "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml",
        }),
        "_rels/.rels": rels(("rId1", f"{NS_REL_DOC}/officeDocument", "word/document.xml")),
        "word/document.xml": document,
    }


def build_xlsx() -> dict[str, str]:
    workbook = (
        f'{XML_DECL}<workbook xmlns="{NS_S}" xmlns:r="{NS_REL_DOC}">'
        '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>'
    )
    sheet = f'{XML_DECL}<worksheet xmlns="{NS_S}"><sheetData/></worksheet>'
    return {
        "[Content_Types].xml": content_types({
            "/xl/workbook.xml": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml",
            "/xl/worksheets/sheet1.xml": "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml",
        }),
        "_rels/.rels": rels(("rId1", f"{NS_REL_DOC}/officeDocument", "xl/workbook.xml")),
        "xl/workbook.xml": workbook,
        "xl/_rels/workbook.xml.rels": rels(
            ("rId1", f"{NS_REL_DOC}/worksheet", "worksheets/sheet1.xml")
        ),
        "xl/worksheets/sheet1.xml": sheet,
    }


# pptx 的包结构是三者中最严格的：presentation 必须挂 slideMaster，
# master 必须挂 layout 与 theme，slide 必须挂 layout，缺一即被判定为损坏。
def build_pptx() -> dict[str, str]:
    empty_sp_tree = (
        "<p:cSld><p:spTree>"
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        "<p:grpSpPr/></p:spTree></p:cSld>"
    )
    clr_map_ovr = "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>"
    pml_attrs = f'xmlns:a="{NS_A}" xmlns:r="{NS_REL_DOC}" xmlns:p="{NS_P}"'

    presentation = (
        f"{XML_DECL}<p:presentation {pml_attrs}>"
        '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
        '<p:sldIdLst><p:sldId id="256" r:id="rId2"/></p:sldIdLst>'
        '<p:sldSz cx="12192000" cy="6858000"/><p:notesSz cx="6858000" cy="9144000"/>'
        "</p:presentation>"
    )
    slide_master = (
        f"{XML_DECL}<p:sldMaster {pml_attrs}>{empty_sp_tree}"
        '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2"'
        ' accent1="accent1" accent2="accent2" accent3="accent3"'
        ' accent4="accent4" accent5="accent5" accent6="accent6"'
        ' hlink="hlink" folHlink="folHlink"/>'
        '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>'
        "</p:sldMaster>"
    )
    slide_layout = f"{XML_DECL}<p:sldLayout {pml_attrs}>{empty_sp_tree}{clr_map_ovr}</p:sldLayout>"
    slide = f"{XML_DECL}<p:sld {pml_attrs}>{empty_sp_tree}{clr_map_ovr}</p:sld>"

    solid_ph = '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    # 必须先存变量再插入 f-string：若在隐式字符串连接中间写 "..." * 3 +，
    # Python 会把前面所有相邻字面量先拼成一个整体再乘 3，产生损坏的 XML。
    effect_styles = "<a:effectStyle><a:effectLst/></a:effectStyle>" * 3
    theme = (
        f'{XML_DECL}<a:theme xmlns:a="{NS_A}" name="Office">'
        "<a:themeElements>"
        '<a:clrScheme name="Office">'
        '<a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>'
        '<a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>'
        '<a:dk2><a:srgbClr val="44546A"/></a:dk2><a:lt2><a:srgbClr val="E7E6E6"/></a:lt2>'
        '<a:accent1><a:srgbClr val="4472C4"/></a:accent1><a:accent2><a:srgbClr val="ED7D31"/></a:accent2>'
        '<a:accent3><a:srgbClr val="A5A5A5"/></a:accent3><a:accent4><a:srgbClr val="FFC000"/></a:accent4>'
        '<a:accent5><a:srgbClr val="5B9BD5"/></a:accent5><a:accent6><a:srgbClr val="70AD47"/></a:accent6>'
        '<a:hlink><a:srgbClr val="0563C1"/></a:hlink><a:folHlink><a:srgbClr val="954F72"/></a:folHlink>'
        "</a:clrScheme>"
        '<a:fontScheme name="Office">'
        '<a:majorFont><a:latin typeface="Calibri Light"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>'
        '<a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>'
        "</a:fontScheme>"
        '<a:fmtScheme name="Office">'
        f"<a:fillStyleLst>{solid_ph * 3}</a:fillStyleLst>"
        '<a:lnStyleLst>'
        f'<a:ln w="6350">{solid_ph}</a:ln><a:ln w="12700">{solid_ph}</a:ln><a:ln w="19050">{solid_ph}</a:ln>'
        "</a:lnStyleLst>"
        f"<a:effectStyleLst>{effect_styles}</a:effectStyleLst>"
        f"<a:bgFillStyleLst>{solid_ph * 3}</a:bgFillStyleLst>"
        "</a:fmtScheme>"
        "</a:themeElements>"
        "</a:theme>"
    )

    return {
        "[Content_Types].xml": content_types({
            "/ppt/presentation.xml": "application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml",
            "/ppt/slideMasters/slideMaster1.xml": "application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml",
            "/ppt/slideLayouts/slideLayout1.xml": "application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml",
            "/ppt/slides/slide1.xml": "application/vnd.openxmlformats-officedocument.presentationml.slide+xml",
            "/ppt/theme/theme1.xml": "application/vnd.openxmlformats-officedocument.theme+xml",
        }),
        "_rels/.rels": rels(("rId1", f"{NS_REL_DOC}/officeDocument", "ppt/presentation.xml")),
        "ppt/presentation.xml": presentation,
        "ppt/_rels/presentation.xml.rels": rels(
            ("rId1", f"{NS_REL_DOC}/slideMaster", "slideMasters/slideMaster1.xml"),
            ("rId2", f"{NS_REL_DOC}/slide", "slides/slide1.xml"),
        ),
        "ppt/slideMasters/slideMaster1.xml": slide_master,
        "ppt/slideMasters/_rels/slideMaster1.xml.rels": rels(
            ("rId1", f"{NS_REL_DOC}/slideLayout", "../slideLayouts/slideLayout1.xml"),
            ("rId2", f"{NS_REL_DOC}/theme", "../theme/theme1.xml"),
        ),
        "ppt/slideLayouts/slideLayout1.xml": slide_layout,
        "ppt/slideLayouts/_rels/slideLayout1.xml.rels": rels(
            ("rId1", f"{NS_REL_DOC}/slideMaster", "../slideMasters/slideMaster1.xml"),
        ),
        "ppt/slides/slide1.xml": slide,
        "ppt/slides/_rels/slide1.xml.rels": rels(
            ("rId1", f"{NS_REL_DOC}/slideLayout", "../slideLayouts/slideLayout1.xml"),
        ),
        "ppt/theme/theme1.xml": theme,
    }


def main() -> None:
    write_package(OUT_DIR / "Template.docx", build_docx())
    write_package(OUT_DIR / "Template.xlsx", build_xlsx())
    write_package(OUT_DIR / "Template.pptx", build_pptx())


if __name__ == "__main__":
    main()
