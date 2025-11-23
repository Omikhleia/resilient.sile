-- Russian localization for re·sil·ient invoices
return {
  invoice = "Счет-фактура",
  invoice_issue_date = "Дата выставления",
  invoice_delivery_date = "Дата поставки",
  invoice_due_date = "Срок оплаты",
  invoice_due_terms = "Оплатить в течение {days} {day_terms}",
  line_id = "ID",
  line_description = "Описание",
  line_quantity = "кол-во", -- "Количество" is too long for usual table columns
  line_unit_price = "Цена за единицу",
  line_tax_rate = "НДС",
  line_gross_amount = "Валовая сумма",
  total_net_amount = "Чистая сумма",
  total_taxes = "Налоги",
  total_amount_due = "Сумма к оплате",
  HUR = function (n) -- Complex pluralization rules for Russian
          if n % 1 ~= 0 then
            return "часов" -- fractional (use genitive plural)
          end
          -- Last two digits to handle 11-14 special case
          local last2 = n % 100
          if last2 >= 11 and last2 <= 14 then
            return "часов" -- genitive plural
          end
          -- Last digit to handle 1,2,3,4 cases
          local last = n % 10
          if last == 1 then
            return "час" -- nominative singular
          end
          if last >= 2 and last <= 4 then
            return "часа" -- genitive singular
          end
          return "часов"
        end,
  day_terms = function (n) -- Singular nominative is "день", but we need genitive forms here
          if n % 1 ~= 0 then
            return "дней"
          end
          if n % 10 == 1 and n % 100 ~= 11 then
            return "дня"
          end
          return "дней"
        end,
  contact = "Контакт",
  date_format = "%d.%m.%Y",
  payment_bank = "Оплата банковским переводом.",
  payment_cheque = "Оплата чеком на имя {payee}.",
}
