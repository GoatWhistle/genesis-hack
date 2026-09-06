import { useMemo } from "react";
import { marked } from "marked";

marked.use({ gfm: true, breaks: false, async: false });

export const Markdown = ({ source }: { source: string }) => {
  const html = useMemo(() => marked.parse(source) as string, [source]);
  return <div className="md" dangerouslySetInnerHTML={{ __html: html }} />;
};
