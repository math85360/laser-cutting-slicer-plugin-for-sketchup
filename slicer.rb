require 'set'
require 'sketchup'
class Slicer
    def initialize
        #@_XXX =
        @ground = [Geom::Point3d.new(0,0,0), Geom::Vector3d.new(0,0,1)]
        @zaxis = Geom::Vector3d.new 0,0,1
    end
    def findOuterWallFaces(entities)
        
    end
    def findOuterFaces(faces)
        wallFaces = Set.new
        floorFaces = Set.new
        otherFaces = Set.new
        faces.each { |face|
            edgeParallelToZAxis = 0
            face.outer_loop.edges.each {|edge|
                if edge.line[1].parallel?(@zaxis)
                    edgeParallelToZAxis = edgeParallelToZAxis+1
                end
            }
            if Geom.intersect_plane_plane(face.plane,@ground)==nil
                floorFaces.add(face)
            else
                if edgeParallelToZAxis == 2
                    wallFaces.add(face)
                else
                    angle = (face.normal.angle_between(@zaxis)/Math::PI).abs
                    if angle>0.0 && angle<1.0
                        otherFaces.add(face)
                    end
                end
            end
        }
        return wallFaces, floorFaces, otherFaces
    end
    def findBiggestFloorFaces(floorFaces) 
        biggestFloorFaces = Set.new()
        groundLevel = nil
        floorFaces.each {|face|
            if biggestFloorFaces.size==0
                biggestFloorFaces.add(face)
            else
                area = biggestFloorFaces.first.area.to_f.round(2)
                area2 = face.area.to_f.round(2)
                #puts area.to_s+" | "+face.area.to_s+" | "+(area < face.area).to_s+" | "+ (area <= face.area).to_s
                if area == area2
                    biggestFloorFaces.add(face)
                elsif area < area2
                    biggestFloorFaces.clear
                    biggestFloorFaces.add(face)
                end
#                groundLevel = biggestFloorFace.outer_loop.vertices[0].position.z
#                face.outer_loop.vertices.each {|v|
#                    pt = Geom::Point3d.new(v.position.x, v.position.y, groundLevel)
#                    if Geom.point_in_polygon_2D(pt, biggestFloorFace.outer_loop.vertices, true)
#                    else
#                        biggestFloorFace = face
#                    end
#                }
            end
        }
        return biggestFloorFaces
    end
    def removeFingerSpace(entities, origFace, face, materialThickness, fingerWidth, collector, faceGroup)
         # Collect edgeUse because face will be modified and datas too ! (Keep in mind that one edge will be shorter with presence of finger joints)
         eu = face.outer_loop.edgeuses.collect { |edgeUse| [edgeUse.start_vertex_normal,edgeUse.edge.start.position,edgeUse.edge.end.position,edgeUse.edge.length]}
         validPoints = Set.new([Sketchup::Face::PointInside, Sketchup::Face::PointOnEdge])
         edgesToErase = Set.new()
         edgesToBuild = Set.new()
         faceToBuild = Set.new()
         faceToCheck = Set.new()
         vertexDone = Set.new()
         eu.each { |start_vertex_normal,start,zend,length|
            # Id is startpoint + endpoint
            myid = (start < zend ? start.to_a+zend.to_a : zend.to_a+start.to_a).to_s
            #puts myid +" | "+collector.include?(myid).to_s
            # Edge is present in collector because one face common to this edge was done, so do invert
            reverse = collector.include?(myid) ? 1 : 0
            # add Id to collector to keep edge already done
            collector.push(myid)
            vector = (zend - start).normalize
            # Get half of the length
            halfLength = length / 2
            perpendicular = start_vertex_normal * vector
            perpendicular.length = perpendicular.length * materialThickness
            # Finger joints width vector
            fingerVector = vector.clone()
            fingerVector.length = fingerWidth
            for p in 0..(halfLength/fingerWidth)
                if p % 2 == reverse
                    for w in 0..1
                        v = vector.clone()
                        starting = w==0 ? start : zend
                        cornerOffset = 0
                        if p==0
                            cornerOffset = (vertexDone.include?(starting.to_a) ? materialThickness : 0)
                            vertexDone.add(starting.to_a)
                        end
                        # Position of the finger joints on the edge starting from start or end
                        v.length = v.length*fingerWidth * (p*2*(0.5-w) - w) + cornerOffset
                        if v.length > halfLength 
                            next
                        end
                        # This finger joints will be on edge middle ?
                        middle = v.length + 2 * (0.5-w) * fingerWidth > halfLength
                        t = Geom::Transformation.translation(v)
                        # Start from begin of edge if before edge middle, else start from end
                        pt1 = starting.transform(t)
                        if middle
                            zVector = vector.clone()
                            # Ensure the length of the middle joints will be ok
                            l = (halfLength - v.length) * 2
                            zVector.length = l<=0 ? fingerWidth * 2 : l
                        else
                            zVector = fingerVector.clone()
                            if cornerOffset>0
                                zVector.length -= cornerOffset
                            end
                        end
                        # Finger joints length parallel translation to edge
                        tWidth = Geom::Transformation.translation(zVector)
                        # Material thickness perpendicular translation to edge
                        tPerp = Geom::Transformation.translation(perpendicular)
                        pt2 = pt1.transform(tPerp)
                        pt3 = pt2.transform(tWidth)
                        pt4 = pt1.transform(tWidth)
                        ptlist = [pt1,pt2,pt3,pt4]
                        corner = !ptlist.none?{|pt| origFace.classify_point(pt)==Sketchup::Face::PointOnVertex}
                        edgesToBuild.add([pt2, pt3, false, corner, ptlist])
                        if !middle || w==0
                            edgesToBuild.add([pt1, pt2, false, corner, ptlist])
                        end
                        if !middle || w==0
                            edgesToBuild.add([pt3, pt4, false, corner, ptlist])
                        end
                        edgesToBuild.add([pt4, pt1, true, corner, ptlist])
                    end
                end
            end
         }
         # Constructs all edges joints
         edgesToBuild.each { |pt1,pt2,erase,corner,ptlist|
            l = entities.add_edges(pt1,pt2)
            if l==nil
                #puts pt1.to_s+pt2.to_s
            else
                puts l.to_s if l.length>1
                #entities.intersect_with false, Geom::Transformation.new, entities, Geom::Transformation.new, false, l
                # Keep outer edge that must be destroy after
                edgesToErase.add(l[0]) if erase
            end
         }
         #puts edgesToBuild.count
         edgesToBuild.delete_if { |pt1,pt2,erase,corner,ptlist| !corner}
         #puts edgesToBuild.count
         cornerEdges = edgesToBuild.collect()
         # Erase all useless edges 
         edgesToErase.each { |e| entities.erase_entities(e) if !e.deleted?}
         edgesToClean = Set.new()
         # Clean when double fingers joints are present in corner
         edges = Set.new(entities.grep(Sketchup::Edge)).each { |e|
            next if e.deleted?
            edgesToBuild.each { |pt1,pt2,erase,corner,ptlist|
                break if e.deleted?
                if ptlist.include?(e.start.position) || ptlist.include?(e.end.position)
                    #puts "OK : "+ptlist.to_s+" | "+e.start.position.to_s+" | "+e.end.position.to_s
                    #e.erase!
                    #e.soft = true 
                end
            }
            next if e.deleted?
            next if e.faces.count > 0
            #e.erase!
         }
    end
    def slice(entities)
        #findOuterFaces(entities)
        
        #zaxis = Sketchup.active_model.axes[2]
        mainGroup = entities.add_group.entities
        faces = Set.new(entities.grep(Sketchup::Face))
        collector = Array.new()
        #innerFaces = findInnerFaces(faces)
        #outerFaces = faces.exclude(innerFaces)
        wallFaces, floorFaces, otherFaces = findOuterFaces(faces)
        biggestFloorFaces = findBiggestFloorFaces(floorFaces)
        puts biggestFloorFaces.to_a.to_s
        if biggestFloorFaces.size==0
        else
            #outerFaces = wallFaces + biggestFloorFace
            outerFaces = wallFaces + biggestFloorFaces
            #group = mainGroup.add_group
            #newface = group.entities.add_face(biggestFloorFace.outer_loop.vertices)
            #removeFingerSpace(group.entities, newface, 0.006.m, 0.020.m, false, collector)
            # Search every faces that intersects with biggestFloorFace
            #
            
            drawingFaces = Set.new(biggestFloorFaces + otherFaces)
            biggestFloorFaces.each { |f|
                f.edges.each {|edge|
                    edge.faces.each { |face|
                        if floorFaces.include?(face)
                        else
                            drawingFaces.add(face)
                        end
                    }
                }
            }

            drawingFaces.each {|face|
                group = mainGroup.add_group
                gents = group.entities
                newface = gents.add_face(face.outer_loop.vertices)
                face.loops.each { |zloop|
                    if zloop.outer?
                    else
                        fFace = gents.add_face(zloop.vertices)
                        gents.erase_entities(fFace)
                    end
                }
                removeFingerSpace(gents, face, newface, 0.006.m, 0.020.m, collector, group)
            }

        end

        #clone face : entities.add_instance(face, IDENTITY)
        
        #make groups of each walls of contiguous face
        #Simplified versions :
        #Walls are all faces with 2 edges // Z
        #Floor are all face // with Face Z=0
        #Others are roof
        #faces.each {|face| }
    end
end

pluginsMenu = UI::menu("Plugins")
item = pluginsMenu.add_item("Slice me for laser cutting please !") {
    model = Sketchup.active_model()
    slicer = Slicer.new
    slicer.slice(model.active_entities)
}