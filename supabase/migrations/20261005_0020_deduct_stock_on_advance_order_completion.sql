-- ============================================================
-- Migration 0020: Deduct stock and record inventory movements on advance order completion
-- Date: 2026-10-05
-- Purpose:
-- Fix bug where completing an advance/deposit order created the invoice and order,
-- but did NOT reduce product/variant stock and did NOT write to public.inventory_movements.
-- Now aligns advance order completion with complete_pos_sale_with_inventory.
-- ============================================================

CREATE OR REPLACE FUNCTION public.complete_advance_order_v2(
  p_order_id uuid,
  p_payment_method text,
  p_final_amount numeric,
  p_coupon_code text DEFAULT NULL,
  p_coupon_percentage numeric DEFAULT 0,
  p_manual_discount numeric DEFAULT 0,
  p_remarks text DEFAULT ''
)
RETURNS TABLE(order_id uuid, invoice_no text, completed_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_advance        public.advance_orders;
  v_order_id       uuid := gen_random_uuid();
  v_invoice        text;
  v_now            timestamptz := now();
  v_items          jsonb;
  v_item           jsonb;
  v_total_discount numeric := 0;

  -- Stock & movement variables
  v_product_id     bigint;
  v_variant_id     uuid;
  v_quantity       numeric;
  v_is_manual      boolean;
  v_item_type      text;
  v_product_name   text;
  v_current_stock  numeric;
  v_barcode_id     uuid;
  v_unit_price     numeric;
  v_line_total     numeric;
  v_name_ta        text;
  v_unit           text;
  v_unit_type      text;
  v_base_quantity  numeric;
  v_image_url      text;
  v_variant_name   text;
  v_source         text;
  v_note           text;
  v_category       text;
BEGIN
  -- Validate payment method
  IF lower(coalesce(p_payment_method, '')) NOT IN ('cash', 'upi', 'card') THEN
    RAISE EXCEPTION 'Select a valid payment method';
  END IF;

  -- Lock and fetch the advance order
  SELECT * INTO v_advance FROM public.advance_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Advance order not found';
  END IF;

  IF v_advance.status = 'cancelled' THEN
    RAISE EXCEPTION 'A cancelled order cannot be completed';
  END IF;

  -- Self-healing & Idempotency check: If invoice or completed order already exists, ensure completed status and return cleanly
  IF v_advance.completed_order_id IS NOT NULL OR v_advance.invoice_number IS NOT NULL OR v_advance.status = 'completed' THEN
    IF v_advance.status != 'completed' THEN
      UPDATE public.advance_orders
      SET status = 'completed',
          updated_at = v_now
      WHERE id = p_order_id;
    END IF;

    RETURN QUERY SELECT 
      coalesce(v_advance.completed_order_id, gen_random_uuid()),
      coalesce(v_advance.invoice_number, 'INV00000000'),
      coalesce(v_advance.completed_at, v_now);
    RETURN;
  END IF;

  -- Build items JSONB - prefer products array, fall back to single product
  v_items := CASE
    WHEN jsonb_typeof(v_advance.products) = 'array' AND jsonb_array_length(v_advance.products) > 0
      THEN v_advance.products
    ELSE jsonb_build_array(
      jsonb_build_object(
        'name',        v_advance.product_name,
        'category',    v_advance.category,
        'description', v_advance.description,
        'quantity',    1,
        'base_price',  v_advance.total_amount,
        'line_total',  v_advance.total_amount,
        'unit',        'piece',
        'unit_type',   'unit',
        'source',      'advance_order'
      )
    )
  END;

  -- 1. Atomic Pre-Validation of Available Stock for All Items (skipping services & manual)
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_items)
  LOOP
    v_product_id := CASE WHEN (v_item ->> 'product_id') ~ '^[0-9]+$' THEN (v_item ->> 'product_id')::bigint ELSE NULL END;
    v_variant_id := CASE WHEN (v_item ->> 'variant_id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN (v_item ->> 'variant_id')::uuid ELSE NULL END;
    v_quantity := GREATEST(COALESCE((v_item ->> 'quantity')::numeric, 0), 0);
    v_is_manual := COALESCE((v_item ->> 'is_manual')::boolean, FALSE);
    v_item_type := LOWER(COALESCE(v_item ->> 'item_type', ''));
    v_product_name := COALESCE(v_item ->> 'product_name', v_item ->> 'name', 'Product');

    -- If variant_id is provided but product_id is not, resolve product_id from variant
    IF v_variant_id IS NOT NULL AND v_product_id IS NULL THEN
      SELECT product_id INTO v_product_id FROM public.product_variants WHERE id = v_variant_id;
    END IF;

    IF NOT v_is_manual AND v_item_type != 'service' AND v_quantity > 0 THEN
      IF v_variant_id IS NOT NULL THEN
        SELECT stock INTO v_current_stock FROM public.product_variants WHERE id = v_variant_id FOR UPDATE;
        IF v_current_stock IS NULL OR v_current_stock < v_quantity THEN
          RAISE EXCEPTION 'Insufficient stock for % (Available: %, Requested: %)', v_product_name, COALESCE(v_current_stock, 0), v_quantity;
        END IF;
      ELSIF v_product_id IS NOT NULL THEN
        SELECT stock_quantity INTO v_current_stock FROM public.products WHERE id = v_product_id FOR UPDATE;
        IF v_current_stock IS NULL OR v_current_stock < v_quantity THEN
          RAISE EXCEPTION 'Insufficient stock for % (Available: %, Requested: %)', v_product_name, COALESCE(v_current_stock, 0), v_quantity;
        END IF;
      END IF;
    END IF;
  END LOOP;

  -- Calculate total discount from manual discount and coupon
  v_total_discount := p_manual_discount + (v_advance.remaining_balance - p_manual_discount - p_final_amount);
  IF v_total_discount < 0 THEN
    v_total_discount := 0;
  END IF;

  -- Generate invoice number using the existing 8-digit sequence
  v_invoice := LPAD(nextval('public.invoice_number_seq')::TEXT, 8, '0');

  -- Create final sale order
  INSERT INTO public.orders (
    id, invoice_no, customer_name, phone, address, user_id,
    items, subtotal, total, status, order_mode, order_type,
    shipping, delivery_charge, discount_amount, manual_discount_amount,
    coupon_code, coupon_percentage, manual_discount_type, manual_discount_value,
    payment_mode, payment_method, created_at, updated_at
  ) VALUES (
    v_order_id, v_invoice,
    v_advance.customer_name, v_advance.phone, v_advance.address, auth.uid(),
    v_items, v_advance.total_amount, greatest(0, v_advance.total_amount - v_total_discount),
    'completed', 'offline', 'advance_order',
    0, 0, v_total_discount, p_manual_discount,
    p_coupon_code, p_coupon_percentage, 'flat', p_manual_discount,
    lower(p_payment_method), lower(p_payment_method),
    v_now, v_now
  );

  -- 2. Insert order items, Deduct Stock & Record SALE Movements
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_items)
  LOOP
    v_product_id := CASE WHEN (v_item ->> 'product_id') ~ '^[0-9]+$' THEN (v_item ->> 'product_id')::bigint ELSE NULL END;
    v_variant_id := CASE WHEN (v_item ->> 'variant_id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN (v_item ->> 'variant_id')::uuid ELSE NULL END;
    v_quantity := GREATEST(COALESCE((v_item ->> 'quantity')::numeric, 1), 0);
    v_unit_price := GREATEST(COALESCE((v_item ->> 'unit_price')::numeric, (v_item ->> 'base_price')::numeric, 0), 0);
    v_line_total := GREATEST(COALESCE((v_item ->> 'line_total')::numeric, ROUND(v_quantity * v_unit_price, 2)), 0);
    v_product_name := COALESCE(NULLIF(TRIM(v_item ->> 'product_name'), ''), NULLIF(TRIM(v_item ->> 'name'), ''), 'Product');
    v_name_ta := COALESCE(v_item ->> 'product_tamil_name', v_item ->> 'tamil_name', '');
    v_unit := COALESCE(NULLIF(v_item ->> 'unit', ''), 'piece');
    v_unit_type := COALESCE(NULLIF(v_item ->> 'unit_type', ''), 'unit');
    v_base_quantity := COALESCE((v_item ->> 'base_quantity')::numeric, 1);
    v_is_manual := COALESCE((v_item ->> 'is_manual')::boolean, FALSE);
    v_item_type := LOWER(COALESCE(v_item ->> 'item_type', ''));
    v_image_url := v_item ->> 'image_url';
    v_variant_name := v_item ->> 'variant_name';
    v_source := COALESCE(v_item ->> 'source', 'advance_order');
    v_note := COALESCE(v_item ->> 'note', v_item ->> 'description', '');
    v_category := COALESCE(v_item ->> 'category', v_advance.category, '');

    -- Resolve product_id from variant if missing
    IF v_variant_id IS NOT NULL AND v_product_id IS NULL THEN
      SELECT product_id INTO v_product_id FROM public.product_variants WHERE id = v_variant_id;
    END IF;

    INSERT INTO public.order_items (
      order_id, product_id, variant_id, product_name, name,
      product_tamil_name, tamil_name, quantity, unit, unit_type,
      base_quantity, base_price, unit_price, line_total, image_url,
      is_manual, variant_name, source, note, category, created_at
    ) VALUES (
      v_order_id, v_product_id, v_variant_id, v_product_name, v_product_name,
      v_name_ta, v_name_ta, v_quantity, v_unit, v_unit_type,
      v_base_quantity, v_unit_price, v_unit_price, v_line_total, v_image_url,
      v_is_manual, v_variant_name, v_source, v_note, v_category, v_now
    );

    -- Deduct Stock and Insert SALE Movement (skip services, manual items, and unlinked custom items)
    IF NOT v_is_manual AND v_item_type != 'service' AND v_quantity > 0 THEN
      IF v_variant_id IS NOT NULL THEN
        SELECT stock INTO v_current_stock FROM public.product_variants WHERE id = v_variant_id;
        SELECT id INTO v_barcode_id FROM public.barcode_registry WHERE variant_id = v_variant_id AND is_active = TRUE LIMIT 1;

        UPDATE public.product_variants
        SET stock = GREATEST(0, stock - v_quantity), updated_at = NOW()
        WHERE id = v_variant_id;

        -- Parent aggregate update
        UPDATE public.products
        SET stock_quantity = (SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE product_id = v_product_id AND is_active = TRUE),
            stock = FLOOR((SELECT COALESCE(SUM(stock), 0) FROM public.product_variants WHERE product_id = v_product_id AND is_active = TRUE))::INTEGER,
            updated_at = NOW()
        WHERE id = v_product_id;

        INSERT INTO public.inventory_movements (
          product_id, variant_id, barcode_id, movement_type,
          quantity_delta, quantity_before, quantity_after,
          reference_type, reference_id, note, created_by_name, created_at
        )
        VALUES (
          v_product_id, v_variant_id, v_barcode_id, 'SALE',
          -v_quantity, v_current_stock, GREATEST(0, v_current_stock - v_quantity),
          'order', v_invoice, 'Advance Order completed: ' || v_advance.deposit_id || ' (Invoice: ' || v_invoice || ')',
          COALESCE(v_advance.created_by_name, ''), v_now
        );

      ELSIF v_product_id IS NOT NULL THEN
        SELECT stock_quantity INTO v_current_stock FROM public.products WHERE id = v_product_id;
        SELECT id INTO v_barcode_id FROM public.barcode_registry WHERE product_id = v_product_id AND variant_id IS NULL AND is_active = TRUE LIMIT 1;

        UPDATE public.products
        SET stock_quantity = GREATEST(0, stock_quantity - v_quantity),
            stock = GREATEST(0, stock - FLOOR(v_quantity)::INTEGER),
            updated_at = NOW()
        WHERE id = v_product_id;

        INSERT INTO public.inventory_movements (
          product_id, variant_id, barcode_id, movement_type,
          quantity_delta, quantity_before, quantity_after,
          reference_type, reference_id, note, created_by_name, created_at
        )
        VALUES (
          v_product_id, NULL, v_barcode_id, 'SALE',
          -v_quantity, v_current_stock, GREATEST(0, v_current_stock - v_quantity),
          'order', v_invoice, 'Advance Order completed: ' || v_advance.deposit_id || ' (Invoice: ' || v_invoice || ')',
          COALESCE(v_advance.created_by_name, ''), v_now
        );
      END IF;
    END IF;
  END LOOP;

  -- Record final payment
  INSERT INTO public.advance_order_payments (
    advance_order_id, payment_type, amount, payment_method, remarks, received_by, received_at
  ) VALUES (
    p_order_id, 'remaining', p_final_amount,
    lower(p_payment_method), coalesce(p_remarks, ''), auth.uid(), v_now
  );

  -- Mark advance order as completed
  UPDATE public.advance_orders SET
    status               = 'completed',
    completed_at         = v_now,
    completed_order_id   = v_order_id,
    invoice_number       = v_invoice,
    final_payment_method = lower(p_payment_method),
    remarks              = CASE WHEN trim(coalesce(p_remarks, '')) = '' THEN remarks ELSE p_remarks END,
    updated_at           = v_now
  WHERE id = p_order_id;

  -- Timeline events
  INSERT INTO public.advance_order_timeline (
    advance_order_id, event_type, label, remarks, created_by, created_at
  ) VALUES
    (p_order_id, 'remaining_payment_received', 'Remaining Payment Received', coalesce(p_remarks, ''), auth.uid(), v_now),
    (p_order_id, 'invoice_generated',          'Invoice Generated',          v_invoice,               auth.uid(), v_now);

  RETURN QUERY SELECT v_order_id, v_invoice, v_now;
END;
$$;

GRANT EXECUTE ON FUNCTION public.complete_advance_order_v2(uuid, text, numeric, text, numeric, numeric, text) TO public, anon, authenticated;

NOTIFY pgrst, 'reload schema';
