interface Props {
  size?: number;
}

export const ArrowRight = ({ size = 16 }: Props) => (
  <svg
    className="arrow-right"
    width={size}
    height={size}
    viewBox="0 0 16 16"
    fill="none"
    stroke="currentColor"
    strokeWidth="1.5"
    strokeLinecap="round"
    strokeLinejoin="round"
    aria-hidden="true"
    focusable="false"
  >
    <path d="M2.5 8h10" />
    <path d="M8.75 4.25 12.5 8l-3.75 3.75" />
  </svg>
);
