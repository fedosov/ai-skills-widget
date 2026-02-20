import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "../../lib/utils";

const buttonVariants = cva(
  "inline-flex items-center justify-center whitespace-nowrap rounded-md border text-[13px] font-medium transition-colors duration-150 focus-visible:outline-none focus-visible:ring-[length:var(--focus-ring-width)] focus-visible:ring-ring disabled:pointer-events-none disabled:opacity-50",
  {
    variants: {
      variant: {
        default:
          "border-primary/55 bg-primary text-primary-foreground shadow-sm hover:bg-primary/92",
        ghost:
          "border-transparent text-foreground hover:bg-accent hover:text-accent-foreground",
        outline:
          "border-border bg-transparent text-foreground hover:bg-accent hover:text-accent-foreground",
        destructive:
          "border-destructive/60 bg-destructive text-destructive-foreground shadow-sm hover:bg-destructive/92",
      },
      size: {
        default: "h-[var(--control-height)] px-3.5",
        sm: "h-[var(--control-height-sm)] px-2.5 text-[12px]",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  },
);

export interface ButtonProps
  extends
    React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, ...props }, ref) => {
    return (
      <button
        className={cn(buttonVariants({ variant, size, className }))}
        ref={ref}
        {...props}
      />
    );
  },
);
Button.displayName = "Button";

export { Button };
