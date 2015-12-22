<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
 xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
 xmlns:wix="http://schemas.microsoft.com/wix/2006/wi">
  <!-- https://ahordijk.wordpress.com/2013/03/26/automatically-add-references-and-content-to-the-wix-installer/ -->
  <!-- http://www.chriskonces.com/using-xslt-with-heat-exe-wix-to-create-windows-service-installs/ -->
  <xsl:output method="xml" indent="yes" />
  <!--<xsl:strip-space elements="*"/>-->
  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>
  <!-- when the ruby.exe filter matches, do nothing -->
  <xsl:template match="wix:Component[wix:File[@Source='$(var.StageDir)\ruby\bin\ruby.exe']]" />
  <xsl:template match="wix:Component[wix:File[@Source='$(var.StageDir)\ruby\bin\rubyw.exe']]" />

  <xsl:key name="tests-search" match="wix:Component[contains(wix:File/@Source, 'test')]" use="@Id" />
  <xsl:template match="wix:Component[key('tests-search', @Id)]" />
  <xsl:template match="wix:ComponentRef[key('tests-search', @Id)]" />

  <xsl:key name="unittests-search" match="wix:Component[contains(wix:File/@Source, 'unittests.')]" use="@Id" />
  <xsl:template match="wix:Component[key('unittests-search', @Id)]" />
  <xsl:template match="wix:ComponentRef[key('unittests-search', @Id)]" />

  <xsl:key name="lth_cat-search" match="wix:Component[contains(wix:File/@Source, 'lth_cat.exe')]" use="@Id" />
  <xsl:template match="wix:Component[key('lth_cat-search', @Id)]" />
  <xsl:template match="wix:ComponentRef[key('lth_cat-search', @Id)]" />
</xsl:stylesheet>
