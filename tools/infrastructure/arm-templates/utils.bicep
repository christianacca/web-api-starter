
@export()
func findFirstBy(list array, key string, value string) object? => first(filter(list, x => x[key] == value))

@export()
func unionBy(firstArray array, secondArray array, key string) array => [
  ...firstArray
  ...filter(secondArray, item => findFirstBy(firstArray, key, item[key]) == null)
]

@export()
func objectValues(obj object) array => map(items(obj), x => x.value)
