import Foundation
import Testing
@testable import BeadsKit

@Test func everyStateThatIsNotReadyHasWordsAndOneThingToDo() {
    #expect(Problem.of(.ready(readyCount: 0)) == nil)
    #expect(Problem.of(.opening) == nil)
    #expect(Problem.of(.needsMigration(dbVersion: 3, appVersion: 5))?.action == .upgradeProject)
    #expect(Problem.of(.needsNewerApp(dbVersion: 7, appVersion: 5))?.action == .updateApp)
    #expect(Problem.of(.legacy)?.action == .openGuide)
    #expect(Problem.of(.server)?.action == nil)
    #expect(Problem.of(.failed(.noAccess("gone"))) == .folderLost)
    let busy = Problem.of(.failed(.busy("database is locked by pid 41")))
    #expect(busy?.title == "Project Is Busy")
    #expect(busy?.detail == "database is locked by pid 41")
    #expect(Problem.of(.failed(.beads("dolt: manifest unreadable")))?.detail == "dolt: manifest unreadable")
}

@Test func aFailedWriteReadsAsASentenceAndKeepsBeadsWords() {
    #expect(BeadsError.busy("locked by pid 41").report == "Another program is writing to this project. Try again in a moment.\nlocked by pid 41")
    #expect(BeadsError.refused("cannot close: blocked by bd-2").report == "cannot close: blocked by bd-2")
    #expect(BeadsError.conflict("").report == "Someone changed this bead first. Nothing was written.")
}
