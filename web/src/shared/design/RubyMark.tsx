import { RUBY_FACETS } from "./rubyFacets";

interface Props {
  size?: number;
}

export const RubyMark = ({ size = 13 }: Props) => (
  <svg
    className="ruby-mark"
    width={size}
    height={size}
    viewBox="3.8 4 117.5 120.1"
    fill="none"
    role="img"
    aria-label="Ruby"
    focusable="false"
  >
    {RUBY_FACETS.map((facet) => (
      <path key={facet.d} d={facet.d} fill={facet.fill} />
    ))}
  </svg>
);
