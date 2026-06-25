class OrderedMap extends Map {
    __New(keyValuePairs*) {
        super.CaseSense := "Off"
        super.__New(keyValuePairs*)
        
        keysArray := []
        keysCount := keyValuePairs.length // 2
        keysArray.length := keysCount

        loop keysCount
            keysArray[A_Index] := keyValuePairs[(A_Index << 1) - 1]

        this.keysArray := keysArray
    }

    __Item[key] {
        set {
            if !this.Has(key)
                this.keysArray.Push(key)

            return super[key] := value
        }
    }

    Clear() {
        super.Clear()
        this.keysArray := []
    }

    Clone() {
        other := super.Clone()
        other.keysArray := this.keysArray.Clone()
        return other
    }

    Delete(key) {
        try {
            removedValue := super.Delete(key)

            caseSense := this.caseSense
            for index, element in this.keysArray {
                areSame := (element is String)
                         ? !StrCompare(element, key, caseSense)
                         : (element = key)

                if areSame {
                    this.keysArray.RemoveAt(index)
                    break
                }
            }

            return removedValue
        } catch Error as err {
            throw Error(err.message, -1, err.extra)
        }
    }

    Set(keyValuePairs*) {
        if (keyValuePairs.length & 1)
            throw ValueError('Invalid number of parameters.', -1)

        keysArray := this.keysArray
        keysCount := keyValuePairs.length // 2
        keysArray.capacity += keysCount

        loop keysCount {
            key := keyValuePairs[(A_Index << 1) - 1]

            if !this.Has(key)
                keysArray.Push(key)
        }

        super.Set(keyValuePairs*)
        return this
    }

    __Enum(*) {
        keyEnum := this.keysArray.__Enum(1)

        keyValEnum(&key := unset, &val := unset) {
            if keyEnum(&key) {
                val := this[key]
                return true
            } else {
                return false
            }
        }

        return keyValEnum
    }
}