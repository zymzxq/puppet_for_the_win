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

  <!-- Ignore test artifacts  -->
  <xsl:template match="wix:Component[contains(wix:File/@Source, 'lth_cat.exe')]" />
  <xsl:template match="wix:Component[contains(wix:File/@Source, 'libfacter_test.exe')]" />
  <xsl:template match="wix:Component[contains(wix:File/@Source, 'libtest.so')]" />
  <xsl:template match="wix:Component[contains(wix:File/@Source, 'libtest1.so')]" />
  <xsl:template match="wix:Component[contains(wix:File/@Source, 'cpp-pcp-client-unittests.exe')]" />
  <xsl:template match="wix:Component[contains(wix:File/@Source, 'libcpp-pcp-client-unittests.dll.a')]" />
  <xsl:template match="wix:Component[contains(wix:File/@Source, 'pxp-agent-unittests.exe')]" />
</xsl:stylesheet>
