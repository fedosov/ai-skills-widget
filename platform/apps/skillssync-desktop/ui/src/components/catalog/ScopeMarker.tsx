import { cn } from "../../lib/utils";

export function ScopeMarker({ scope }: { scope: string }) {
  const scopeLabel = scope === "global" ? "Global" : "Project";

  return (
    <span className="inline-flex items-center gap-1">
      <span
        aria-hidden="true"
        title={scopeLabel}
        className={cn(
          "inline-block h-2 w-2 rounded-full",
          scope === "global" ? "bg-emerald-500/80" : "bg-sky-500/80",
        )}
      />
      <span className="text-[10px] text-muted-foreground">{scopeLabel}</span>
    </span>
  );
}
