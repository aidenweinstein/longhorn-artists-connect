import type { CSSProperties } from "react";

/**
 * Renders a white-on-transparent PNG as a shape filled with the current text
 * color, so app assets can be tinted orange, white, etc. with Tailwind text-*.
 */
export default function MaskImage({
  src,
  ratio,
  label,
  className = "",
}: {
  src: string;
  ratio: number;
  label?: string;
  className?: string;
}) {
  const style: CSSProperties = {
    aspectRatio: ratio,
    backgroundColor: "currentColor",
    WebkitMaskImage: `url(${src})`,
    maskImage: `url(${src})`,
    WebkitMaskSize: "contain",
    maskSize: "contain",
    WebkitMaskRepeat: "no-repeat",
    maskRepeat: "no-repeat",
    WebkitMaskPosition: "center",
    maskPosition: "center",
  };
  return (
    <span
      role={label ? "img" : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
      className={`inline-block shrink-0 ${className}`}
      style={style}
    />
  );
}
