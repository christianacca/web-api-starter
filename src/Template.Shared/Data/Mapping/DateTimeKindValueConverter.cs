using Microsoft.EntityFrameworkCore.Storage.ValueConversion;

namespace Template.Shared.Data.Mapping;

public class DateTimeKindValueConverter : ValueConverter<DateTime, DateTime> {
  public DateTimeKindValueConverter(DateTimeKind kind, ConverterMappingHints? mappingHints = null)
    : base(v => v.ToUniversalTime(), v => DateTime.SpecifyKind(v, kind), mappingHints) {
  }
}