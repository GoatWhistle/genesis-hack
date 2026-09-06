import { MARK_FACETS, MARK_FILL, MARK_SIDE } from "./markFacets";

interface Props {
  size?: number;
  className?: string;
}

export const Mark = ({ size = 22, className }: Props) => (
  <svg
    className={className ? `mark ${className}` : "mark"}
    width={size}
    height={size}
    viewBox="0 0 128 128"
    fill="none"
    aria-hidden="true"
    focusable="false"
  >
    <defs>
      <linearGradient id="mark-sheen" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0%" stopColor="#fff" stopOpacity="0" />
        <stop offset="45%" stopColor="#fff" stopOpacity="0.55" />
        <stop offset="60%" stopColor="#fff" stopOpacity="0" />
      </linearGradient>
      <clipPath id="mark-body">
        {MARK_FACETS.map((facet) => (
          <path key={facet.d} d={facet.d} />
        ))}
      </clipPath>
    </defs>

    <g>
      {MARK_FACETS.map((facet) => (
        <path
          key={facet.d}
          className={`mark-facet mark-${MARK_SIDE[facet.tone]}`}
          d={facet.d}
          fill={MARK_FILL[facet.tone]}
        />
      ))}
    </g>

    <g clipPath="url(#mark-body)">
      <rect className="mark-sheen" x="-128" y="0" width="128" height="128" fill="url(#mark-sheen)" />
    </g>
  </svg>
);
