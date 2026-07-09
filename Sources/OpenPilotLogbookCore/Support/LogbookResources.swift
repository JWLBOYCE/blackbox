import Foundation

public enum LogbookResources {
    public static var earthBlueMarbleURL: URL? {
        Bundle.module.url(forResource: "earth-blue-marble", withExtension: "jpg")
    }
}
